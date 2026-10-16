"""Upgrade retains owned data and records a prior-file backup."""
from __future__ import annotations
import subprocess
import os
import sys
import tempfile
import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parents[1]

class UpgradeTests(unittest.TestCase):
    def test_upgrade_backups_modified_core_but_preserves_knowledge(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            home, kb = base/'tools', base/'knowledge'
            env=os.environ.copy();env['LOCALAPPDATA']=str(base/'user-config');env['XDG_CONFIG_HOME']=str(base/'xdg-config')
            init = subprocess.run([sys.executable, '-X', 'utf8', str(SRC/'scripts/init_workspace.py'),
                '--install-root', str(home), '--knowledge-root', str(kb)],
                text=True, capture_output=True, env=env)
            self.assertEqual(init.returncode, 0, init.stderr)
            marker = kb/'brand.md'
            marker.write_text('用户自有品牌定位，请勿覆盖', encoding='utf-8')
            legacy = home/'AGENTS.md'
            legacy.write_text('旧版本用户已有规则', encoding='utf-8')
            preview = subprocess.run([sys.executable, '-X', 'utf8', str(SRC/'scripts/upgrade_core.py'),
                '--root',str(home)],capture_output=True,text=True)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertIn('PREVIEW ONLY',preview.stdout)
            self.assertEqual(legacy.read_text(encoding='utf-8'),'旧版本用户已有规则')
            run = subprocess.run([sys.executable, '-X', 'utf8', str(SRC/'scripts/upgrade_core.py'),
                '--root',str(home),'--apply'],capture_output=True,text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(legacy.read_bytes(),(SRC/'AGENTS.md').read_bytes())
            self.assertEqual(marker.read_text(encoding='utf-8'),'用户自有品牌定位，请勿覆盖')
            self.assertEqual((home/'references/release.json').read_bytes(),(SRC/'references/release.json').read_bytes())
            backups=list((home/'backups').glob('core-before-*/AGENTS.md'))
            self.assertEqual(len(backups),1)
            self.assertEqual(backups[0].read_text(encoding='utf-8'),'旧版本用户已有规则')

if __name__ == '__main__':
    unittest.main()