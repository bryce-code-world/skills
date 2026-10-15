#!/usr/bin/env python3
"""Offline end-to-end smoke for WORKSPACE and deterministic media tooling.

Uses a static test fixture (not an actual AI review), synthetic original materials,
a test-tone audio track and ffmpeg. NOT a real Agent, MoneyPrinterTurbo, or platform
publishing. Does not accept credentials or call external APIs.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_paths import output_directory

PLATFORMS = ('xiaohongshu', 'douyin', 'tencent', 'bilibili', 'kuaishou', 'wechat_oa', 'zhihu')
SCENES = [
    ('先确定服务谁', '内容团队要提高效率，先明确目标用户和实际问题。', '0x16334f'),
    ('把创作拆成流程', '再把选题、脚本、审核和剪辑，拆成能够复用的步骤。', '0x225950'),
    ('AI 自动检查质量', '内容质量不合格自动返工，任务范围内的制作不再反复人工审批。', '0x62462e'),
]


def run(args: list[str], log: list[dict]):
    done = subprocess.run(args, text=True, capture_output=True, timeout=150)
    log.append({'command': [Path(args[0]).name] + args[1:], 'exit_code': done.returncode,
                'stderr_tail': done.stderr[-650:]})
    if done.returncode:
        raise RuntimeError(f'{args[0]} failed: {done.stderr[-700:]}')
    return done.stdout


def jwrite(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def srtstamp(sec: int) -> str:
    return f'{sec//3600:02d}:{(sec//60)%60:02d}:{sec%60:02d},000'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    p = argparse.ArgumentParser(description='Offline fixtures only; never posts to accounts.')
    p.add_argument('--install-root', required=True)
    p.add_argument('--fixture-render', action='store_true', help='Use synthetic fixture to test ffmpeg only; not a real AI review.')
    p.add_argument('--output-id', default=None)
    a = p.parse_args()
    root = Path(a.install_root).resolve()
    cfg = json.loads((root / 'config/workspace.json').read_text(encoding='utf-8'))
    knowledge = Path(cfg['knowledge_root'])
    for key in ('brand.md', 'audience.md', 'review-rules.md'):
        if not (knowledge / key).is_file():
            raise RuntimeError(f'Missing knowledge file: {key}')
    if cfg.get('auto_publish') is not False:
        raise RuntimeError('Not safe: auto_publish must be false')
    output_id = a.output_id or 'offline-smoke-' + uuid4().hex[:8]
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}', output_id):
        raise ValueError('输出内容 ID 只能使用字母、数字、下划线或连字符，最长64位')
    target = output_directory(root, cfg) / output_id
    if target.exists():
        raise RuntimeError(f'Output already exists; refusing overwrite: {target}')
    target.mkdir(parents=True)
    trace: list[dict] = []
    b = (knowledge / 'brand.md').read_text(encoding='utf-8')
    aud = (knowledge / 'audience.md').read_text(encoding='utf-8')
    rules = (knowledge / 'review-rules.md').read_text(encoding='utf-8')
    (target / 'brief.md').write_text(
        '# 离线流程测试选题（非 AI 生成）\n\n'
        '主题：小团队如何建立可重复的 AI 内容制作流程\n\n'
        '企业知识库摘录（测试时读取本地文件）：\n\n'
        f'{b[:360]}\n\n{aud[:260]}\n', encoding='utf-8')
    narration = ''.join(scene[1] for scene in SCENES)
    (target / 'narration.txt').write_text(narration, encoding='utf-8')
    (target / 'script.md').write_text(
        '# 离线视频脚本（静态测试示例）\n\n' +
        '\n'.join(f'- {i*10}–{(i+1)*10}s：{scene[0]}。{scene[1]}' for i, scene in enumerate(SCENES)) + '\n',
        encoding='utf-8')
    jwrite(target / 'script.json', {
        'content_id': output_id, 'test_only': True, 'script_source': 'static_smoke_fixture_not_codex',
        'duration_seconds': 30,
        'knowledge_files': {name: sha(knowledge / name) for name in ('brand.md', 'audience.md', 'review-rules.md')},
        'scenes': [{'start': i*10, 'end': (i+1)*10, 'title': s[0], 'narration': s[1]} for i, s in enumerate(SCENES)]})
    # The review confirms input material was loaded; this is deliberately NOT model judgement.
    jwrite(target / 'review.json', {
        'test_only': True, 'review_method': 'offline_deterministic_fixture_not_ai_review',
        'review_standard_sha256': hashlib.sha256(rules.encode()).hexdigest(),
        'result': 'PASS_CANDIDATE_FIXTURE_ONLY',
        'gate_status': 'blocked_without_real_ai_review',
        'issues': ['本示例未验证外部事实，也未通过真实业务审核']})
    trace.append({'test': 'fixture_is_not_genuine_ai_review', 'passed': True})
    if not a.fixture_render:
        jwrite(target / 'smoke-report.json', {'result': 'BLOCKED_AT_AI_REVIEW_AS_EXPECTED', 'commands': trace})
        print('BLOCKED: static fixture is not a genuine AI review. Use --fixture-render to test FFmpeg only.')
        return 0
    trace.append({'test': 'test_only_fixture_render', 'test_only': True})
    for cmd in ('ffmpeg', 'ffprobe'):
        if shutil.which(cmd) is None:
            raise RuntimeError(f'Missing offline demo command: {cmd}')
    mats = target / 'materials'
    mats.mkdir()
    for i, s in enumerate(SCENES):
        mp4 = mats / f'generated_test_clip_{i+1}.mp4'
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
             '-i', f'color=c={s[2]}:s=360x640:r=15:d=10', '-t', '10',
             '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', str(mp4)], trace)
    jwrite(target / 'materials.json', {'test_only': True, 'source': 'generated_color_clips',
            'license': 'original_generated_test_fixture',
            'items': [{'path': str(p.relative_to(target)), 'seconds': 10} for p in sorted(mats.glob('*.mp4'))]})
    srt = target / 'video' / 'subtitles.srt'
    srt.parent.mkdir()
    srt.write_text(''.join(f'{i+1}\n{srtstamp(10*i)} --> {srtstamp(10*(i+1))}\n{scene[1]}\n\n'
                           for i, scene in enumerate(SCENES)), encoding='utf-8')
    audio = target / 'video' / 'synthetic_test_tone.wav'
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','lavfi','-i',
         'sine=frequency=330:duration=30:sample_rate=16000','-c:a','pcm_s16le',str(audio)],trace)
    input_txt = target / 'video' / 'concat.txt'
    input_txt.write_text(''.join("file '%s'\n" % p.absolute().as_posix() for p in sorted(mats.glob('*.mp4'))), encoding='utf-8')
    out = target / 'video' / 'master.mp4'
    # Video uses three synthetic original clips. TTS is a smoke-quality voice, NOT professional production voice.
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0',
         '-i', str(input_txt), '-i', str(audio), '-filter_complex',
         f"[0:v]subtitles={srt.as_posix()}:force_style='FontName=Noto Sans CJK SC,FontSize=14,PrimaryColour=&H00FFFFFF,Outline=2,MarginV=50'[v]",
         '-map', '[v]', '-map', '1:a', '-af', 'apad', '-t', '30', '-r', '15',
         '-c:v', 'libx264', '-preset', 'ultrafast', '-c:a', 'aac', '-b:a', '64k',
         '-movflags', '+faststart', '-pix_fmt', 'yuv420p', str(out)], trace)
    probe = json.loads(run(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(out)], trace))
    jwrite(target / 'video' / 'ffprobe.json', probe)
    streams = probe['streams']
    vs = next((s for s in streams if s.get('codec_type') == 'video'), {})
    au = next((s for s in streams if s.get('codec_type') == 'audio'), {})
    assert vs.get('width') == 360 and vs.get('height') == 640, 'Wrong video aspect'
    assert au and float(probe['format']['duration']) >= 29.9, 'Missing audio or video too short'
    trace.append({'test': 'real_ffmpeg_render_30s_9_16_audio', 'passed': True,
                  'resolution': [vs['width'], vs['height']],
                  'seconds': float(probe['format']['duration'])})
    coversrc = target / 'video' / 'cover.jpg'
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', '1', '-i', str(out), '-frames:v', '1', str(coversrc)], trace)
    for p in PLATFORMS:
        pd = target / 'platforms' / p
        pd.mkdir(parents=True)
        if p in ('wechat_oa', 'zhihu'):
            (pd / 'article.md').write_text('# 小团队如何让 AI 内容生产更稳定\n\n'
                '这是一份**离线测试生成的示例稿**，请替换为审核通过的企业真实内容。\n\n'
                '确定服务对象、沉淀生产规范、AI 自动核查并交付成果。\n', encoding='utf-8')
        jwrite(pd / 'package.json', {
            'content_id': output_id, 'platform': p, 'test_only': True, 'status': 'prepared_not_published',
            'account_alias': None, 'publish_scope': {},
            'title': '小团队如何建立 AI 内容生产流程（测试勿发）',
            'description': '仅用于验证离线内容包结构，不得用于正式发布。',
            'tags': ['测试', 'AI内容流程'],
            'video': str(out.relative_to(target)) if p not in ('wechat_oa', 'zhihu') else None})
    jwrite(target / 'publish-ledger.json', {'test_only': True, 'dry_run': True,
        'accounts_authorized': False, 'platforms': {p: 'not_submitted' for p in PLATFORMS}})
    report = {'result': 'OFFLINE_SMOKE_PASSED_NOT_REAL_END_TO_END',
       'proven': ['workspace knowledge files read', 'fixture review is not genuine AI review',
                  'synthetic 3-clip media generation', 'offline synthetic test audio and Chinese SRT',
                  'real ffmpeg 9:16 30 second MP4', '7 platform content packages prepared',
                  'no publish credentials or calls'],
       'not_proven': ['Agent Skills actual invocation', 'MoneyPrinterTurbo execution',
                      'social-auto-upload execution', 'any MCP operation',
                      'genuine review quality', 'external platform login or posting'],
       'commands': trace, 'generated_at_utc': datetime.now(timezone.utc).isoformat()}
    jwrite(target / 'smoke-report.json', report)
    print('PASSED_OFFLINE_MEDIA_SMOKE:', out)
    print('REPORT:', target / 'smoke-report.json')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, AssertionError) as exc:
        print('FAIL:', exc, file=sys.stderr)
        raise SystemExit(2)