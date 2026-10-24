"""Deterministic narration assembly and per-shot audio checks.

All resampling and decoding are delegated to FFmpeg. RMS tests detect very
short/mostly silent audio, not speech intelligibility or voice naturalness.
"""
from __future__ import annotations

import array
import json
import math
import os
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


def _run(command, *, binary=False):
    p = subprocess.run([str(x) for x in command], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=not binary,
                       timeout=120, **({} if binary else {"encoding": "utf-8", "errors": "replace"}))
    if p.returncode:
        detail = p.stderr.decode("utf8", "replace") if binary else p.stderr
        raise ValueError(f"音频工具执行失败：{detail[-600:]}")
    return p.stdout


def assess_pcm(pcm: bytes, rate: int, shots: list[dict]) -> dict:
    """Flag insufficient active sound inside shots which promise spoken narration."""
    if rate <= 0 or len(pcm) % 2 or not shots:
        raise ValueError("无效的 PCM 音频或分镜")
    audio = array.array("h")
    audio.frombytes(pcm)
    if sys.byteorder != "little":
        audio.byteswap()
    frame = max(1, rate // 5)  # 200 ms windows, robust to ordinary punctuation pauses
    total_seconds = sum(float(x["seconds"]) for x in shots)
    errors = []
    pacing_warnings=[]
    if abs(len(audio) / rate - total_seconds) > 0.55:
        errors.append(f"音频时长与分镜总时长不一致：{len(audio)/rate:.2f}s vs {total_seconds:.2f}s")
    offset = 0
    details = []
    for n, shot in enumerate(shots, 1):
        seconds = float(shot["seconds"])
        if seconds <= 0:
            raise ValueError("分镜时长必须大于零")
        end = min(len(audio), round((offset + seconds) * rate))
        start = min(len(audio), round(offset * rate))
        offset += seconds
        rms_values = []
        for pos in range(start, end, frame):
            chunk = audio[pos:min(pos + frame, end)]
            rms_values.append(math.sqrt(sum(int(v)*int(v) for v in chunk) / len(chunk)) / 32768)
        peak = max(rms_values, default=0)
        threshold = max(0.003, peak * 0.12)
        active = [x >= threshold for x in rms_values]
        active_fraction = sum(active) / len(active) if active else 0.0
        longest = run = 0
        for flag in active:
            run = 0 if flag else run + 1
            longest = max(longest, run)
        longest_silence = round(longest * frame / rate, 2)
        item = {"shot": n, "seconds": seconds, "active_fraction": round(active_fraction, 3),
                "longest_silence_seconds": longest_silence, "threshold_rms": round(threshold, 4)}
        details.append(item)
        if str(shot.get("voiceover", "")).strip() and longest_silence >= 0.8:
            pacing_warnings.append({"shot":n,"silence_seconds":longest_silence,
                "severity":"review_or_fix" if longest_silence>=1.2 else "check_pacing",
                "note":"能量空档只是风险提示；应检查原音轨的句尾与切镜，不能自动判定不自然"})
        if str(shot.get("voiceover", "")).strip() and (
                active_fraction < 0.45 or longest_silence > max(2.0, min(3.0, seconds * 0.5))):
            errors.append(f"分镜 {n} 有效声音不足或长时间静音：active={active_fraction:.0%}，"
                          f"longest_silence={longest_silence:.1f}s；请复核配音/重采样/字幕")
    return {"result": "PASS" if not errors else "BLOCK", "method": "energy_check_not_speech_recognition",
            "shots": details, "issues": errors,"pacing_warnings":pacing_warnings}


def inspect_wav(path: Path, shots: list[dict]) -> dict:
    with wave.open(str(path), "rb") as w:
        if w.getsampwidth() != 2 or w.getnchannels() != 1 or w.getcomptype() != "NONE":
            raise ValueError("配音 WAV 必须为未压缩 16-bit mono PCM")
        return assess_pcm(w.readframes(w.getnframes()), w.getframerate(), shots)


def inspect_video(ffmpeg: str, ffprobe: str, video: Path, shots: list[dict]) -> dict:
    info = json.loads(_run([ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", video]))
    tracks = info.get("streams", [])
    if not any(s.get("codec_type") == "audio" for s in tracks):
        raise ValueError("MP4 缺少音频轨道")
    if not any(s.get("codec_type") == "video" for s in tracks):
        raise ValueError("MP4 缺少视频轨道")
    duration = float(info.get("format", {}).get("duration", 0))
    pcm = _run([ffmpeg, "-v", "error", "-i", video, "-vn", "-map", "0:a:0",
                "-ac", "1", "-ar", "16000", "-f", "s16le", "-acodec", "pcm_s16le", "-"], binary=True)
    result = assess_pcm(pcm, 16000, shots)
    result["video_seconds"] = round(duration, 3)
    return result


def mix_takes(ffmpeg: str, ffprobe: str, shots: list[dict], takes: list[Path],
              output: Path, *, replace=False) -> dict:
    """Combine per-shot TTS files without changing their playback speed."""
    if not shots or len(shots) != len(takes):
        raise ValueError("TTS 文件数量必须与分镜数量一致")
    if output.exists() and not replace:
        raise ValueError("配音文件已存在；如需返工请显式 --replace")
    lead_in = 0.15
    labels, cmd, start, parts = [], [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"], 0.0, []
    for i, (shot, path) in enumerate(zip(shots, takes)):
        path = Path(path).expanduser().resolve()
        if not path.is_file() or path.suffix.lower() != ".wav":
            raise ValueError(f"分镜 {i+1} 缺少真实 WAV 语音：{path}")
        duration = float(json.loads(_run([ffprobe, "-v", "error", "-show_format",
                                         "-of", "json", path]))["format"]["duration"])
        slot = float(shot["seconds"])
        if not math.isfinite(duration) or duration <= 0:
            raise ValueError(f"分镜 {i+1} 配音时长必须是有限正数")
        if not math.isfinite(slot) or slot <= lead_in:
            raise ValueError(f"分镜 {i+1} 槽位须为有限时长且大于 {lead_in:.2f}s 起点余量")
        if duration > slot - lead_in:
            raise ValueError(f"分镜 {i+1} 语音 {duration:.2f}s 超出槽位 {slot:.2f}s；"
                             f"需计入 {lead_in:.2f}s 起点余量，请调整文案或延长分镜，禁止加速音频硬塞")
        cmd.extend(["-i", path])
        label = f"a{i}"
        parts.append(f"[{i}:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=mono,"
                     f"adelay={round((start+lead_in)*1000)}[{label}]")
        labels.append(f"[{label}]")
        start += slot
    if len(labels) == 1:
        graph = ";".join(parts) + f";{labels[0]}apad,atrim=duration={start:.3f}[out]"
    else:
        graph = ";".join(parts) + ";" + "".join(labels) + (
            f"amix=inputs={len(labels)}:duration=longest:normalize=0,"
            f"apad,atrim=duration={start:.3f}[out]")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix=".voiceover-", suffix=".wav", delete=False) as tmp:
        target = Path(tmp.name)
    try:
        _run(cmd + ["-filter_complex", graph, "-map", "[out]", "-c:a", "pcm_s16le", "-ar", "48000",
                    "-ac", "1", target])
        checked = inspect_wav(target, shots)
        if checked["result"] != "PASS":
            raise ValueError("装配后语音存在异常：" + "; ".join(checked["issues"]))
        os.replace(target, output)
        return checked
    finally:
        if target.exists():
            target.unlink()

def mix_continuous(ffmpeg: str, ffprobe: str, shots: list[dict], source: Path,
                   output: Path, *, replace=False) -> dict:
    """Convert one whole spoken performance without splitting it at scene boundaries.

    All sample-rate and channel transformations use FFmpeg, never hand-written PCM.
    No voice is accelerated or cut to fit an individual visual shot.
    """
    src=Path(source).expanduser().resolve()
    if not src.is_file() or src.suffix.lower()!=".wav":
        raise ValueError("连续旁白必须使用真实的单段 PCM WAV；不接受逐镜头拼接的替身")
    if not shots or any(float(s.get("seconds",0))<=0 for s in shots):
        raise ValueError("连续配音要求有效镜头时长")
    if output.exists() and not replace:
        raise ValueError("连续旁白文件已经存在；需要 --replace 才能重新装配")
    duration=float(json.loads(_run([ffprobe,"-v","error","-show_format","-of","json",src]))["format"]["duration"])
    total=sum(float(s["seconds"]) for s in shots)
    if not math.isfinite(duration) or duration<=0 or duration>total+.05:
        raise ValueError(f"连续旁白 {duration:.2f}s 超过视频总时长 {total:.2f}s，禁止加速和裁尾音")
    if total-duration>1.2:
        raise ValueError(f"连续旁白比视频短 {total-duration:.2f}s；禁止用长静音补时长")
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent,prefix=".continuous-",
                                     suffix=".wav",delete=False) as tmp:
        staging=Path(tmp.name)
    try:
        _run([ffmpeg,"-hide_banner","-loglevel","error","-y","-i",src,
              "-vn","-af",f"aresample=48000,aformat=sample_fmts=s16:channel_layouts=mono,"
              f"apad,atrim=duration={total:.3f}",
              "-c:a","pcm_s16le","-ar","48000","-ac","1",staging])
        verdict=inspect_wav(staging,shots)
        if verdict["result"]!="PASS":
            raise ValueError("连续语音异常："+ "; ".join(verdict["issues"]))
        os.replace(staging,output)
        return {**verdict,"mode":"continuous","source_duration_seconds":round(duration,3),
                "video_duration_seconds":round(total,3)}
    finally:
        staging.unlink(missing_ok=True)
