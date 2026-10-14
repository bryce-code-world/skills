"""Offline checks: downloader manifest, entrypoints, fake uv Python bootstrap.
No external network or unknown executables are downloaded during tests.
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
import os
import platform
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def load_bootstrap():
    spec=importlib.util.spec_from_file_location('bootstrap_assets',ROOT/'scripts/bootstrap_assets.py')
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj)
    return obj


class BootstrapRegression(unittest.TestCase):
    def test_manifest_and_shell_pins_agree(self):
        d=json.loads((ROOT/'config/bootstrap-assets.json').read_text('utf-8'))
        self.assertEqual(d['uv']['version'],'0.12.19')
        self.assertEqual(d['python']['version'],'3.12')
        shell=(ROOT/'SETUP-UNIX.sh').read_text('utf-8')
        for key in ('linux-x64','linux-arm64','macos-x64','macos-arm64'):
            asset=d['uv']['assets'][key]
            self.assertIn(asset['file'],shell)
            self.assertIn(asset['sha256'],shell)
        ps=(ROOT/'SETUP-WINDOWS.ps1').read_text('utf-8')
        self.assertIn('bootstrap-assets.json',ps)
        self.assertIn('Invoke-WebRequest',ps)
        self.assertIn('python install',shell)
        self.assertIn("'python','install','3.12'",ps)

    def test_tampered_binary_rejected_by_hash(self):
        b=load_bootstrap()
        with tempfile.TemporaryDirectory() as tmp:
            dest=Path(tmp)/'badfile'
            dest.write_bytes(b'not an official binary')
            self.assertFalse(b.verify(dest,{'sha256':'0'*64}))
            self.assertFalse(b.verify(dest,{'md5':'0'*32}))
            self.assertTrue(b.verify(dest,{'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}))
            with self.assertRaises(ValueError):b.download('https://example.com/fake',dest,{'sha256':'0'*64},offline=True)

    @unittest.skipUnless(platform.system()=='Linux' and platform.machine() in ('x86_64','amd64'), 'shell test on Linux x64')
    def test_bash_first_boot_and_idempotence_with_fake_uv(self):
        # Simulates uv and Python provider in an offline sandbox. Does NOT claim actual Python 3.12 download.
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            root=base/'工具 with spaces'
            knowledge=base/'企业 data'
            uvdir=root/'runtime/bootstrap/uv';uvdir.mkdir(parents=True)
            fakepy=base/'mock-managed-python'
            fakepy.write_text('#!/bin/sh\nif [ "${1:-}" = "-c" ];then exit 0;fi\nexec '+sys.executable+' "$@"\n',encoding='utf-8')
            fakepy.chmod(0o755)
            fakeuv=uvdir/'uv'
            fakeuv.write_text('#!/bin/sh\ncase "$1 $2" in\n  "--version "*) echo "uv 0.12.19";;\n  "python install") mkdir -p "$UV_PYTHON_INSTALL_DIR/stub";;\n  "python find") echo "'+str(fakepy)+'";;\n  *) exit 2;;\nesac\n',encoding='utf-8')
            fakeuv.chmod(0o755)
            args=['bash',str(ROOT/'SETUP-UNIX.sh'),'--install-root',str(root),'--knowledge-root',str(knowledge),'--non-interactive','--skip-ffmpeg']
            first=subprocess.run(args,text=True,capture_output=True,timeout=30)
            self.assertEqual(first.returncode,0,first.stdout+'\n'+first.stderr)
            cfg=json.loads((root/'config/workspace.json').read_text('utf-8'))
            self.assertEqual(cfg['knowledge_root'],str(knowledge))
            self.assertTrue((root/'run-studio.sh').exists())
            self.assertTrue((root/'SETUP-WINDOWS.ps1').exists())
            self.assertTrue((root/'config/bootstrap-assets.json').exists())
            (knowledge/'brand.md').write_text('自有内容不覆盖',encoding='utf-8')
            second=subprocess.run(args,text=True,capture_output=True,timeout=30)
            self.assertEqual(second.returncode,0,second.stderr)
            self.assertEqual((knowledge/'brand.md').read_text('utf-8'),'自有内容不覆盖')
            doctor=subprocess.run(['bash',str(root/'run-studio.sh'),'doctor','--scope','core','--strict'],text=True,capture_output=True,timeout=30)
            self.assertEqual(doctor.returncode,0,doctor.stdout+'\n'+doctor.stderr)
            nested=base/'nested'
            bad=subprocess.run(['bash',str(ROOT/'SETUP-UNIX.sh'),'--install-root',str(root),'--knowledge-root',str(root/'nested'),'--non-interactive','--skip-ffmpeg'],text=True,capture_output=True,timeout=15)
            self.assertEqual(bad.returncode,2)
            self.assertFalse((root/'nested').exists())

if __name__=='__main__':unittest.main(verbosity=2)
