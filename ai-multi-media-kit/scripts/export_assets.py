#!/usr/bin/env python3
"""Package user-owned content, NOT installed third-party tools or login credentials.

Security: rejects symlink inputs and excludes conventional secret/token/cookie names,
hidden dirs and runtime dirs. Review assets manually before sharing externally.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_paths import output_directory
from upgrade_core import owned_files

EXCLUDED = re.compile(r'(?:^|[._-])(cookie|session|secret|token|password|private|credential|auth|\.env)(?:[._-]|$)', re.I)
EXCLUDED_DIRS = {'auth', 'runtime', '.git', '.venv', 'cache', 'logs', 'node_modules', '__pycache__', 'secrets'}


def safe_files(root: Path):
    if root.is_symlink():
        raise ValueError(f'Symlink root refused: {root}')
    for candidate in root.rglob('*'):
        rel = candidate.relative_to(root)
        if candidate.is_symlink():
            continue
        if any(part in EXCLUDED_DIRS or part.startswith('.') for part in rel.parts):
            continue
        if EXCLUDED.search(rel.name):
            continue
        if candidate.is_file():
            yield candidate, rel


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--install-root', required=True)
    p.add_argument('--destination', required=True)
    args = p.parse_args()
    root = Path(args.install_root).expanduser().resolve()
    cfg = json.loads((root/'config/workspace.json').read_text(encoding='utf-8'))
    knowledge = Path(cfg['knowledge_root']).expanduser().resolve()
    projects = output_directory(root, cfg)
    out = Path(args.destination).expanduser().resolve()
    if knowledge == root or root in knowledge.parents or knowledge in root.parents:
        raise ValueError('Knowledge root must be separate from install root')
    if out.is_relative_to(root) or out.is_relative_to(knowledge) or out.is_relative_to(projects):
        raise ValueError('Export destination must be outside the exported data roots')
    items: list[tuple[Path,str]] = []
    for folder,label in ((knowledge,'knowledge'),(projects,'outputs')):
        if folder.exists():
            for file,rel in safe_files(folder):
                items.append((file, f'{label}/{rel.as_posix()}'))
    for file, label in ((root/'config/material-sources.json','materials/sources.json'),
                        (root/'runtime/materials-index.json','materials/index.json')):
        if file.is_file() and not file.is_symlink():
            items.append((file,label))
    # Preserve the same relative paths used by SKILL.md and the runtime scripts.
    for rel in owned_files(root):
        file = root / rel
        if (file.is_file() and not any(p.is_symlink() for p in (file, *file.parents))
                and not EXCLUDED.search(file.name)):
            items.append((file, f'skill/{rel}'))
    # External/NAS source clips are not copied; only their index and provenance are exported.
    out.parent.mkdir(parents=True, exist_ok=True)
    manifest = {'format': 'ai-media-studio-owner-export-v2', 'contains_credentials': 'not_verified_by_content_scan',
                'files': []}
    with ZipFile(out, 'w', compression=ZIP_DEFLATED, compresslevel=6) as zipout:
        for file, label in sorted(items, key=lambda t:t[1]):
            raw = file.read_bytes()
            zipout.writestr(label,raw)
            manifest['files'].append({'path': label, 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})
        zipout.writestr('export-manifest.json', json.dumps(manifest,ensure_ascii=False,indent=2))
    print(json.dumps({'path': str(out), 'file_count': len(items),
        'file_size': out.stat().st_size, 'warning': 'Review contents before external sharing; embedded secrets in text are not detectable automatically'},
        ensure_ascii=False,indent=2))

if __name__ == '__main__':
    main()
