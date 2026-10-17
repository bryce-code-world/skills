"""Host-declared creator identity. Paths stay compatible with existing content IDs."""
from __future__ import annotations

import re
from datetime import datetime, timezone
from uuid import uuid4

SLUG = re.compile(r'^[a-z0-9][a-z0-9-]*$')
ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')


def slug(value: str, label: str, limit: int) -> str:
    if not isinstance(value, str) or not SLUG.fullmatch(value) or len(value) > limit:
        raise ValueError(f'{label} 须为小写英文/数字/连字符，最多 {limit} 字符')
    return value


def new_identity(args) -> dict:
    """Legacy --id stays readable; new --topic/--agent mode cannot omit its creator."""
    agent, topic = getattr(args, 'agent', None), getattr(args, 'topic', None)
    cid = getattr(args, 'id', None)
    run = getattr(args, 'run_id', None)
    model = getattr(args, 'model', None)
    if model is not None and (not model.strip() or len(model) > 128 or any(ord(c) < 32 for c in model)):
        raise ValueError('model 必须是真实且不含控制字符的模型名称；未知则不传')
    if not agent:
        if not cid or topic or run or model or getattr(args, 'parent_id', None):
            raise ValueError('新任务必须提供 --topic 和 --agent；旧调用只保留 --id 兼容入口')
        if not ID.fullmatch(cid):
            raise ValueError('内容 ID 非法')
        return {'schema': 3, 'content_id': cid, 'topic_id': cid, 'agent_id': 'unknown',
                'model_id': None, 'run_id': None, 'identity_source': 'legacy-unspecified'}
    agent = slug(agent, 'agent', 16)
    topic = slug(topic, 'topic', 24)
    run = slug(run or (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S').lower() + '-' + uuid4().hex[:6]),
               'run-id', 22)
    generated = f'{topic}-{agent}-{run}'
    if cid and cid != generated:
        raise ValueError(f'指定 --agent 时内容 ID 必须为 {generated}；建议省略 --id 自动生成')
    if not ID.fullmatch(generated):
        raise ValueError('生成的内容 ID 超过64字符，请缩短 topic/agent/run-id')
    return {'schema': 4, 'content_id': generated, 'topic_id': topic, 'agent_id': agent,
            'model_id': model, 'run_id': run, 'identity_source': 'host-declared-not-authenticated'}


def provenance(content: dict) -> dict:
    """Never infer creator identity from old folder names or a model brand."""
    return {'content_id': content.get('content_id'), 'topic_id': content.get('topic_id'),
            'agent_id': content.get('agent_id') or 'unknown', 'model_id': content.get('model_id'),
            'run_id': content.get('run_id'), 'parent': content.get('parent'),
            'skill_version': content.get('skill_version')}
