"""Audio engineering regression: catches fast/TTS-corrupt or mostly silent narration."""
from __future__ import annotations

import array
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))


def ffbin(name):
    specified = os.environ.get("AI_MEDIA_TEST_" + name.upper())
    return specified if specified and Path(specified).is_file() else shutil.which(name)


def tone(seconds, sample_rate=16000):
    samples = array.array("h", [int(9000 * math.sin(2 * math.pi * 280 * i / sample_rate))
                                for i in range(int(seconds * sample_rate))])
    return samples.tobytes()


def wav(path, seconds, hz=22050):
    samples = tone(seconds, hz)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(hz)
        w.writeframes(samples)


class MediaAudioTests(unittest.TestCase):
    def test_mostly_silent_shot_is_blocked_even_with_valid_audio_track(self):
        from media_audio import assess_pcm
        shots = [{"seconds": 9, "voiceover": "这段九秒镜头必须有正常语音"}]
        bad = tone(1.8) + b"\x00\x00" * int(7.2 * 16000)
        result = assess_pcm(bad, 16000, shots)
        self.assertEqual(result["result"], "BLOCK", result)
        self.assertGreater(result["shots"][0]["longest_silence_seconds"], 3)
        self.assertLess(result["shots"][0]["active_fraction"], 0.4)

    def test_healthy_per_shot_narration_passes_with_short_pauses(self):
        from media_audio import assess_pcm
        shots = [{"seconds": 4, "voiceover": "一段正常配音"}, {"seconds": 4, "voiceover": "另一段正常配音"}]
        good = (tone(3.3) + b"\x00\x00" * (int(0.7 * 16000))) * 2
        result = assess_pcm(good, 16000, shots)
        self.assertEqual(result["result"], "PASS", result)

    def test_tone_only_cannot_prove_natural_speech(self):
        from media_audio import assess_pcm
        result = assess_pcm(tone(3), 16000, [{"seconds": 3, "voiceover": "需要正常配音"}])
        self.assertEqual(result["result"], "PASS")
        self.assertEqual(result["method"], "energy_check_not_speech_recognition")

    @unittest.skipUnless(ffbin("ffmpeg") and ffbin("ffprobe"), "FFmpeg not installed")
    def test_ffmpeg_video_gate_rejects_fast_voice_plus_long_silence(self):
        from media_audio import inspect_video
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.mp4"
            ffmpeg = ffbin("ffmpeg")
            p = subprocess.run(
                [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                 "-f", "lavfi", "-i", "color=c=navy:s=160x280:r=12:d=5",
                 "-f", "lavfi", "-i", "sine=frequency=400:duration=0.8:sample_rate=22050",
                 "-filter_complex", "[1:a]apad[a]", "-map", "0:v", "-map", "[a]",
                 "-t", "5", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
                 "-c:a", "aac", str(bad)], capture_output=True, text=True, timeout=45)
            self.assertEqual(p.returncode, 0, p.stderr)
            result = inspect_video(str(ffbin("ffmpeg")), str(ffbin("ffprobe")), bad,
                                   [{"seconds": 5, "voiceover": "不能五秒中只播零点八秒"}])
            self.assertEqual(result["result"], "BLOCK", result)

    @unittest.skipUnless(ffbin("ffmpeg") and ffbin("ffprobe"), "FFmpeg not installed")
    def test_ffmpeg_voiceover_mix_resamples_without_speedup(self):
        from media_audio import mix_takes, inspect_wav
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            takes = [base / "one.wav", base / "two.wav"]
            wav(takes[0], 2.5)
            wav(takes[1], 2.5)
            target = base / "narration.wav"
            shots = [{"seconds": 3, "voiceover": "第一段"}, {"seconds": 3, "voiceover": "第二段"}]
            mix_takes(str(ffbin("ffmpeg")), str(ffbin("ffprobe")), shots, takes, target)
            self.assertTrue(target.is_file())
            with wave.open(str(target), "rb") as f:
                self.assertEqual(f.getframerate(), 48000)
                self.assertEqual(f.getnchannels(), 1)
                self.assertAlmostEqual(f.getnframes() / f.getframerate(), 6, delta=0.05)
            checked = inspect_wav(target, shots)
            self.assertEqual(checked["result"], "PASS", checked)

    @unittest.skipUnless(ffbin("ffmpeg") and ffbin("ffprobe"), "FFmpeg not installed")
    def test_studio_video_ready_blocks_broken_audio_despite_ai_pass(self):
        """An AI-written PASS must not override the deterministic audible-duration failure."""
        import studio
        from unittest.mock import patch
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            with patch.dict(os.environ, {"LOCALAPPDATA": str(base / "user-config"),
                                         "XDG_CONFIG_HOME": str(base / "xdg-config"),
                                         "PATH": str(Path(ffbin("ffmpeg")).parent) + os.pathsep + os.environ.get("PATH", "")}):
                root, kb = base / "tools", base / "knowledge"
                init = subprocess.run([sys.executable, "-X", "utf8",
                    str(ROOT / "scripts/init_workspace.py"), "--install-root", str(root),
                    "--knowledge-root", str(kb)], capture_output=True, text=True, timeout=25)
                self.assertEqual(init.returncode, 0, init.stderr)
                created = subprocess.run([sys.executable, "-X", "utf8",
                    str(ROOT / "scripts/studio.py"), "--root", str(root), "new",
                    "--id", "damaged-voice", "--title", "异常语音示例"],
                    capture_output=True, text=True, timeout=25)
                self.assertEqual(created.returncode, 0, created.stderr)
                d = root / "outputs" / "damaged-voice"
                script = {"content_id": "damaged-voice", "title": "真实测试异常配音", "duration_seconds": 5,
                          "narration": "这一段语音应该持续五秒钟。",
                          "shots": [{"seconds": 5, "voiceover": "这一段语音应该持续五秒钟。", "visual": "原创测试图形"}],
                          "platforms": {name: {"title": "测试视频", "tags": []} for name in studio.PLATFORMS}}
                (d / "script.json").write_text(json.dumps(script, ensure_ascii=False), encoding="utf8")
                hashfile = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
                sha = hashfile(d / "script.json")
                rules_sha = hashfile(kb / "review-rules.md")
                (d / "review.json").write_text(json.dumps({
                    "result": "PASS", "checks": [{"rule": "脚本", "result": "PASS"}],
                    "facts_to_verify": [], "issues": [], "script_sha256": sha,
                    "review_standard_sha256": rules_sha}), encoding="utf8")
                dest = d / "video" / "master.mp4"
                dest.parent.mkdir(exist_ok=True)
                make = subprocess.run([ffbin("ffmpeg"), "-loglevel", "error", "-y",
                    "-f", "lavfi", "-i", "color=c=navy:s=160x280:r=12:d=5",
                    "-f", "lavfi", "-i", "sine=frequency=400:duration=0.8:sample_rate=22050",
                    "-filter_complex", "[1:a]apad[a]", "-map", "0:v", "-map", "[a]",
                    "-t", "5", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", str(dest)], capture_output=True, text=True, timeout=45)
                self.assertEqual(make.returncode, 0, make.stderr)
                video_sha = hashfile(dest)
                (d / "video/render.json").write_text(json.dumps({
                    "engine": "import", "script_sha256": sha, "video_sha256": video_sha}), encoding="utf8")
                (d / "video/review.json").write_text(json.dumps({
                    "result": "PASS", "checks": [{"rule": "音频", "result": "PASS"}],
                    "facts_to_verify": [], "issues": [], "video_sha256": video_sha,
                    "script_sha256": sha, "review_standard_sha256": rules_sha}), encoding="utf8")
                with self.assertRaisesRegex(ValueError, "静音|声音"):
                    studio.ensure_video_ready(d, kb, root)


if __name__ == "__main__":
    unittest.main()
