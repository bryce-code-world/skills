"""Offline checks: downloader manifest, entrypoints, fake uv Python bootstrap.
No external network or unknown executables are downloaded during tests.
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
import os
import platform
import shutil
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
        self.assertIn('workspace_locator.py', shell)
        self.assertIn('workspace_locator.py', ps)

    def test_tampered_binary_rejected_by_hash(self):
        b=load_bootstrap()
        with tempfile.TemporaryDirectory() as tmp:
            dest=Path(tmp)/'badfile'
            dest.write_bytes(b'not an official binary')
            self.assertFalse(b.verify(dest,{'sha256':'0'*64}))
            self.assertFalse(b.verify(dest,{'md5':'0'*32}))
            self.assertTrue(b.verify(dest,{'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}))
            with self.assertRaises(ValueError):b.download('https://example.com/fake',dest,{'sha256':'0'*64},offline=True)

    @unittest.skipUnless(os.name == "nt" and shutil.which("powershell.exe"), "Windows PowerShell only")
    def test_windows_bootstrap_reuses_registered_workspace_without_provisioning(self):
        """Onboarding a second local Agent must not re-download or rewrite the environment."""
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            tool, knowledge = base / "reused tools", base / "知识库"
            env = os.environ.copy()
            env["LOCALAPPDATA"] = str(base / "isolated local app data")
            isolated_skill = base / "another Agent Skill"
            shutil.copytree(ROOT, isolated_skill, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            first = subprocess.run([sys.executable, "-X", "utf8",
                str(isolated_skill / "scripts/init_workspace.py"), "--install-root", str(tool),
                "--knowledge-root", str(knowledge), "--remember"],
                text=True, capture_output=True, env=env, timeout=25)
            self.assertEqual(first.returncode, 0, first.stderr)
            original=(tool/'config/workspace.json').read_bytes()
            invoke=["powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
                    "-File",str(ROOT/'SETUP-WINDOWS.ps1'),"-NonInteractive"]
            reused=subprocess.run(invoke, capture_output=True, text=True, encoding='utf-8',
                                  errors='replace', env=env, timeout=30)
            self.assertEqual(reused.returncode, 0, reused.stderr)
            self.assertIn("REUSE_EXISTING_WORKSPACE", reused.stdout)
            self.assertEqual((tool/'config/workspace.json').read_bytes(), original)
            self.assertFalse((tool/'runtime/bootstrap/uv/uv.exe').exists())
            other=base/"duplicate tools"
            blocked=subprocess.run(invoke+["-InstallRoot",str(other),"-KnowledgeRoot",str(base/'other-kb')],
                                   capture_output=True,text=True,encoding='utf8',errors='replace',
                                   env=env,timeout=30)
            self.assertEqual(blocked.returncode,2)
            self.assertFalse(other.exists())
            index=Path(env['LOCALAPPDATA'])/'ai-multi-media-kit'/'local-install.json'
            index.write_text('{invalid-json',encoding='utf8')
            invalid=subprocess.run(invoke,capture_output=True,text=True,encoding='utf8',
                                   errors='replace',env=env,timeout=30)
            self.assertEqual(invalid.returncode,2)
            self.assertIn('locator',invalid.stderr.lower())
            self.assertFalse((tool/'runtime/bootstrap/uv/uv.exe').exists())

    @unittest.skipUnless(platform.system()=='Linux' and platform.machine() in ('x86_64','amd64'), 'shell test on Linux x64')
    def test_bash_first_boot_and_idempotence_with_fake_uv(self):
        # Simulates uv and Python provider in an offline sandbox. Does NOT claim actual Python 3.12 download.
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            env=os.environ.copy()
            env['XDG_CONFIG_HOME']=str(base/'isolated-user-config')
            # Run setup from an isolated Skill installation so tests cannot overwrite
            # the user's real source-local installation pointer.
            isolated_skill=base/'skill-src'
            shutil.copytree(ROOT,isolated_skill,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
            root=base/'工具 with spaces'
            knowledge=base/'企业 data'
            uvdir=root/'runtime/bootstrap/uv';uvdir.mkdir(parents=True)
            fakepy=base/'mock-managed-python'
            fakepy.write_text('#!/bin/sh\nif [ "${1:-}" = "-c" ];then exit 0;fi\nexec '+sys.executable+' "$@"\n',encoding='utf-8')
            fakepy.chmod(0o755)
            fakeuv=uvdir/'uv'
            fakeuv.write_text('#!/bin/sh\ncase "$1 $2" in\n  "--version "*) echo "uv 0.12.19";;\n  "python install") mkdir -p "$UV_PYTHON_INSTALL_DIR/stub";;\n  "python find") echo "'+str(fakepy)+'";;\n  *) exit 2;;\nesac\n',encoding='utf-8')
            fakeuv.chmod(0o755)
            args=['bash',str(isolated_skill/'SETUP-UNIX.sh'),'--install-root',str(root),'--knowledge-root',str(knowledge),'--non-interactive','--skip-ffmpeg']
            first=subprocess.run(args,text=True,capture_output=True,timeout=30,env=env)
            self.assertEqual(first.returncode,0,first.stdout+'\n'+first.stderr)
            cfg=json.loads((root/'config/workspace.json').read_text('utf-8'))
            self.assertEqual(cfg['knowledge_root'],str(knowledge))
            self.assertTrue((root/'run-studio.sh').exists())
            self.assertTrue((root/'SETUP-WINDOWS.ps1').exists())
            self.assertTrue((root/'config/bootstrap-assets.json').exists())
            locator=json.loads((isolated_skill/'config/local-install.json').read_text('utf-8'))
            self.assertEqual(locator['install_root'],str(root))
            shared=json.loads((Path(env['XDG_CONFIG_HOME'])/'ai-multi-media-kit/local-install.json').read_text('utf8'))
            self.assertEqual(shared['install_root'],str(root))
            self.assertFalse((root/'config/local-install.json').exists())
            (knowledge/'brand.md').write_text('自有内容不覆盖',encoding='utf-8')
            second=subprocess.run(args,text=True,capture_output=True,timeout=30,env=env)
            self.assertEqual(second.returncode,0,second.stderr)
            self.assertIn('REUSE_EXISTING_WORKSPACE',second.stdout)
            self.assertEqual((knowledge/'brand.md').read_text('utf-8'),'自有内容不覆盖')
            doctor=subprocess.run(['bash',str(root/'run-studio.sh'),'doctor','--scope','core','--strict'],text=True,capture_output=True,timeout=30)
            self.assertEqual(doctor.returncode,0,doctor.stdout+'\n'+doctor.stderr)
            nested=base/'nested'
            bad=subprocess.run(['bash',str(isolated_skill/'SETUP-UNIX.sh'),'--install-root',str(root),'--knowledge-root',str(root/'nested'),'--non-interactive','--skip-ffmpeg'],text=True,capture_output=True,timeout=15,env=env)
            self.assertEqual(bad.returncode,2)
            self.assertFalse((root/'nested').exists())

if __name__=='__main__':unittest.main(verbosity=2)
