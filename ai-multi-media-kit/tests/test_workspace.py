"""Fast offline regression tests for workspace and data-safety guarantees."""
from __future__ import annotations
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent


def py(script: str, *args: str):
    return subprocess.run([sys.executable, str(ROOT/'scripts'/script), *map(str,args)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)


class WorkspaceRegression(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base=Path(self.tmp.name)
        self.root=base/'tools'
        self.knowledge=base/'company'
        self.first=py('init_workspace.py','--install-root',self.root,'--knowledge-root',self.knowledge)
        self.assertEqual(self.first.returncode,0,self.first.stderr)

    def test_idempotent_init(self):
        path=self.knowledge/'brand.md'
        path.write_text('用户数据不可覆盖', encoding='utf-8')
        again=py('init_workspace.py','--install-root',self.root,'--knowledge-root',self.knowledge)
        self.assertEqual(again.returncode,0,again.stderr)
        self.assertEqual(path.read_text(encoding='utf-8'),'用户数据不可覆盖')

    def test_wrong_knowledge_path_refused_without_mutation(self):
        wrong=self.root.parent/'new_company'
        bad=py('init_workspace.py','--install-root',self.root,'--knowledge-root',wrong)
        self.assertEqual(bad.returncode,2)
        self.assertFalse(wrong.exists())

    def test_nested_roots_rejected(self):
        nested=self.root/'nested'
        bad=py('init_workspace.py','--install-root',self.root,'--knowledge-root',nested)
        self.assertEqual(bad.returncode,2)
        self.assertFalse(nested.exists())

    def test_doctor_strict_reports_uninstalled(self):
        output=self.root.parent/'doctor.json'
        c=py('doctor.py','--install-root',self.root,'--scope','all','--strict','--json-output',output)
        self.assertEqual(c.returncode,1)
        result=json.loads(output.read_text(encoding='utf-8'))
        self.assertFalse(result['readiness'])
        self.assertTrue(result['missing'])
        self.assertEqual(result['scope'],'presence_only_not_platform_acceptance')

    def test_review_gate_blocks_render(self):
        c=py('offline_smoke.py','--install-root',self.root,'--output-id','needs-approval')
        self.assertEqual(c.returncode,0,c.stderr)
        output=self.root/'outputs'/'needs-approval'
        self.assertTrue((output/'review.json').exists())
        self.assertFalse((output/'video/master.mp4').exists())
        c2=py('offline_smoke.py','--install-root',self.root,'--output-id','needs-approval')
        self.assertNotEqual(c2.returncode,0)

    def test_export_keeps_assets_but_not_secrets(self):
        (self.knowledge/'cookie-token.txt').write_text('not_exported',encoding='utf-8')
        (self.knowledge/'business-notes.txt').write_text('user-owned content',encoding='utf-8')
        archive=self.root.parent/'export.zip'
        result=py('export_assets.py','--install-root',self.root,'--destination',archive)
        self.assertEqual(result.returncode,0,result.stderr)
        with ZipFile(archive) as z:
            self.assertIn('knowledge/business-notes.txt', z.namelist())
            self.assertIn('skill/SKILL.md',z.namelist())
            self.assertNotIn('knowledge/cookie-token.txt',z.namelist())
            self.assertNotIn('skill/workspace.json',z.namelist())


if __name__=='__main__':
    unittest.main(verbosity=2)
