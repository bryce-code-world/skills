"""Offline TTS input preparation. A text preflight is NEVER a pronunciation verdict.

Known risky phrases cause REVISE; the Agent rewrites the canonical spoken script
and subtitles in context, then regenerates the plan. No vendor SSML is invented.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
import unicodedata
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def text_key(text: str) -> str:
    return ''.join(c for c in text if not c.isspace() and not unicodedata.category(c).startswith('P'))


def load_rules(root: Path, knowledge: Path) -> tuple[list[dict], str]:
    baseline = root / 'config/pronunciation.json'
    if not baseline.is_file():
        baseline = Path(__file__).resolve().parents[1] / 'config/pronunciation.json'
    files = [baseline]
    user = knowledge / 'pronunciation.json'
    if user.exists():
        files.append(user)
    rules = {}
    for path in files:
        data = json.loads(path.read_text(encoding='utf-8-sig'))
        if not isinstance(data, dict) or data.get('schema') != 1 or not isinstance(data.get('terms'), list):
            raise ValueError(f'发音词典格式无效：{path.name}')
        for row in data['terms']:
            if not isinstance(row, dict) or any(not isinstance(row.get(k), str) or not row[k].strip()
                    for k in ('term', 'expected_reading', 'suggestion')):
                raise ValueError('发音词条必须包含非空 term、expected_reading、suggestion')
            if len(row['term']) > 80 or len(row['suggestion']) > 1000:
                raise ValueError('发音词条过长')
            rules[row['term']] = {k: row[k] for k in ('term', 'expected_reading', 'suggestion')}
    ordered = sorted(rules.values(), key=lambda x: x['term'])
    sha = digest(json.dumps(ordered, ensure_ascii=False, sort_keys=True).encode('utf8'))
    return ordered, sha


def build_plan(script: dict, script_sha: str, rules: list[dict], rules_sha: str,
               engine: str, voice: str) -> dict:
    for name, value in (('tts-engine', engine), ('voice', voice)):
        if not isinstance(value, str) or not value.strip() or len(value) > 128 or any(ord(c) < 32 for c in value):
            raise ValueError(f'{name} 必须是当前实际使用的服务/音色标识，不包含凭据')
    texts = []
    for i, shot in enumerate(script['shots'], 1):
        spoken = shot.get('voiceover')
        if not isinstance(spoken, str) or not spoken.strip():
            raise ValueError(f'分镜 {i} 缺少正式口播 voiceover')
        if re.search(r'<[^>]+>', spoken):
            raise ValueError('口播须为普通文本；不能把未经适配验证的 SSML/phoneme 标签送给 TTS')
        if 'subtitle_text' in shot:
            if not isinstance(shot['subtitle_text'], str) or text_key(shot['subtitle_text']) != text_key(spoken):
                raise ValueError(f'分镜 {i} 字幕与口播不一致；改稿后须同步字幕')
        if 'subtitle_lines' in shot:
            lines = shot['subtitle_lines']
            if not isinstance(lines, list) or not all(isinstance(x, str) for x in lines) or text_key(''.join(lines)) != text_key(spoken):
                raise ValueError(f'分镜 {i} 字幕行与口播不一致')
        texts.append(spoken.strip())
    if text_key(script['narration']) != text_key(''.join(texts)):
        raise ValueError('narration 与分镜口播不一致，发音改稿须同步更新')
    findings = [{'shot': i, **row} for i, text in enumerate(texts, 1) for row in rules if row['term'] in text]
    takes = [{'shot': i, 'text': text, 'text_sha256': digest(text.encode('utf8')),
              'text_file': f'work/tts-inputs/{script_sha}/shot-{i:03d}.txt'} for i, text in enumerate(texts, 1)]
    return {'schema': 1, 'content_id': script['content_id'], 'script_sha256': script_sha,
            'lexicon_sha256': rules_sha, 'tts_engine': engine, 'voice': voice,
            'result': 'REVISE' if findings else 'READY', 'findings': findings, 'takes': takes,
            'pronunciation_verified': False,
            'scope': 'known_lexicon_text_preflight_not_audio_or_complete_chinese_g2p'}


def validate_plan(d: Path, root: Path, knowledge: Path) -> dict | None:
    """Recompute text/rule bindings; a hand-written READY cannot remove findings."""
    content = json.loads((d/'content.json').read_text('utf8'))
    target = d/'work/speech-plan.json'
    if not target.is_file():
        if content.get('schema', 3) >= 4:
            raise ValueError('缺少发音准备：先执行 studio speech-plan，再生成 TTS WAV')
        return None  # Existing projects are not rewritten or silently migrated.
    actual = json.loads(target.read_text('utf8'))
    if not isinstance(actual,dict):
        raise ValueError('发音准备记录格式无效，请重新执行 speech-plan')
    raw = (d/'script.json').read_bytes()
    script = json.loads(raw)
    rules, rules_sha = load_rules(root, knowledge)
    expected = build_plan(script, digest(raw), rules, rules_sha, actual.get('tts_engine'), actual.get('voice'))
    if expected['result'] != 'READY':
        raise ValueError('发音风险尚未处理：请按语境改稿并重新执行 speech-plan')
    for key in expected:
        if actual.get(key) != expected[key]:
            raise ValueError(f'发音准备记录已过期或被改写（{key}）；重新执行 speech-plan')
    for take in expected['takes']:
        path = d/take['text_file']
        if path.is_symlink() or not path.resolve().is_relative_to(d.resolve()) or not path.is_file() or digest(path.read_bytes()) != take['text_sha256']:
            raise ValueError('TTS 输入稿不存在或被修改；重新执行 speech-plan')
    return actual


def validate_audio_review(review: dict, duration: float, plan_sha: str) -> None:
    """Require explicit, version-bound listening evidence, not an ASR/energy claim.

    Evidence is host-declared; this validator cannot authenticate a model's senses.
    """
    item = review.get('pronunciation_check', {})
    if not isinstance(item, dict) or item.get('result') != 'PASS' or item.get('method') != 'actual_audio_review':
        raise ValueError('缺少实际音频发音验收；ASR/能量检测不能代替试听')
    if item.get('speech_plan_sha256') != plan_sha:
        raise ValueError('发音验收未绑定当前 speech-plan')
    evidence = item.get('evidence')
    if not isinstance(evidence, list) or not evidence:
        raise ValueError('发音验收缺少带时间点的实际试听依据')
    for row in evidence:
        if not isinstance(row, dict):
            raise ValueError('发音验收依据格式错误')
        start, end = row.get('start'), row.get('end')
        if any(isinstance(t, bool) or not isinstance(t, (int, float)) or not math.isfinite(t) for t in (start, end)):
            raise ValueError('发音验收时间点无效')
        if not 0 <= start < end <= duration + 0.55 or not isinstance(row.get('note'), str) or not row['note'].strip():
            raise ValueError('发音验收依据须包含有效时间段与实际听到的内容说明')
