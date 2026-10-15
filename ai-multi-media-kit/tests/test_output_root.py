"""User-selected project directory: CLI integration and backward compatibility.

These tests use OS temporary directories and cannot modify an installed workspace.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]


class OutputRootTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        local=patch.dict(os.environ,{'LOCALAPPDATA':str(base/'user-config'), 'XDG_CONFIG_HOME':str(base/'xdg-config')})
        local.start(); self.addCleanup(local.stop)
        self.install = base / "tool runtime"
        self.knowledge = base / "企业知识库"
        self.output = base / "持久项目成果"
        self.exported = base / "backup.zip"

    def run_script(self, name, *args):
        return subprocess.run([sys.executable, "-X", "utf8", str(SOURCE / "scripts" / name),
                               *map(str, args)], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=45)

    def initialize(self, output=None, specify=True):
        args = ["--install-root", self.install, "--knowledge-root", self.knowledge]
        if specify:
            args += ["--output-root", output or self.output]
        return self.run_script("init_workspace.py", *args)

    def test_custom_output_root_is_used_by_all_content_commands_smoke_and_export(self):
        first = self.initialize()
        self.assertEqual(first.returncode, 0, first.stderr)
        cfg = json.loads((self.install / "config/workspace.json").read_text("utf8"))
        self.assertEqual(cfg["output_root"], str(self.output.resolve()))
        self.assertTrue(self.output.is_dir())
        self.assertFalse((self.install / "outputs").exists())
        created = self.run_script("studio.py", "--root", self.install, "new",
                                  "--id", "demo-001", "--title", "项目创作目录测试")
        self.assertEqual(created.returncode, 0, created.stderr)
        content_dir = self.output / "demo-001"
        self.assertTrue((content_dir / "content.json").exists())
        status = self.run_script("studio.py", "--root", self.install, "status", "--id", "demo-001")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertTrue(json.loads(status.stdout)["script_exists"] is False)
        smoke = self.run_script("offline_smoke.py", "--install-root", self.install,
                                "--output-id", "smoke-001")
        self.assertEqual(smoke.returncode, 0, smoke.stderr)
        self.assertTrue((self.output / "smoke-001" / "smoke-report.json").is_file())
        exported = self.run_script("export_assets.py", "--install-root", self.install,
                                   "--destination", self.exported)
        self.assertEqual(exported.returncode, 0, exported.stderr)
        with zipfile.ZipFile(self.exported) as bundle:
            self.assertIn("outputs/demo-001/content.json", bundle.namelist())
            self.assertIn("outputs/smoke-001/smoke-report.json", bundle.namelist())
        self.assertEqual(self.initialize(specify=False).returncode, 0)

    def test_legacy_and_missing_setting_remain_in_install_outputs(self):
        old = self.initialize(specify=False)
        self.assertEqual(old.returncode, 0, old.stderr)
        folder = self.install / "outputs"
        self.assertTrue(folder.is_dir())
        cfg_path = self.install / "config/workspace.json"
        cfg = json.loads(cfg_path.read_text("utf8"))
        self.assertEqual(cfg["output_root"], str(folder.resolve()))
        cfg.pop("output_root")
        cfg_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2)+"\n", encoding="utf8")
        again = self.initialize(specify=False)
        self.assertEqual(again.returncode, 0, again.stderr)
        created = self.run_script("studio.py", "--root", self.install, "new",
                                  "--id", "old-001", "--title", "兼容旧工作区")
        self.assertEqual(created.returncode, 0, created.stderr)
        self.assertTrue((folder / "old-001" / "content.json").is_file())

    def test_conflicting_output_reconfiguration_is_rejected_without_mutation(self):
        self.assertEqual(self.initialize().returncode, 0)
        old_cfg = (self.install / "config/workspace.json").read_bytes()
        marker = self.output / "user-created.txt"
        marker.write_text("retain me", encoding="utf8")
        other = self.output.parent / "elsewhere"
        attempt = self.initialize(output=other)
        self.assertEqual(attempt.returncode, 2)
        self.assertFalse(other.exists())
        self.assertEqual((self.install / "config/workspace.json").read_bytes(), old_cfg)
        self.assertEqual(marker.read_text("utf8"), "retain me")

    def test_nested_or_overlapping_output_is_rejected_before_creating_roots(self):
        for i, bad in enumerate((self.install, self.install / "other",
                                 self.knowledge, self.knowledge / "project",
                                 self.install.parent)):
            with self.subTest(index=i):
                result = self.initialize(output=bad)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertFalse((self.install / "config/workspace.json").exists())
                self.assertFalse(self.knowledge.exists())

    def test_existing_custom_output_missing_must_not_be_recreated_silently(self):
        self.assertEqual(self.initialize().returncode, 0)
        self.output.rmdir()  # Test-created empty project output directory
        again = self.initialize(specify=False)
        self.assertEqual(again.returncode, 2)
        self.assertIn("output_root", again.stderr)
        self.assertFalse(self.output.exists())

    def test_studio_refuses_missing_persisted_custom_output_directory(self):
        self.assertEqual(self.initialize().returncode, 0)
        self.output.rmdir()
        created = self.run_script("studio.py", "--root", self.install, "new",
                                  "--id", "unexpected-001", "--title", "禁止静默重建")
        self.assertEqual(created.returncode, 2, created.stderr)
        self.assertIn("项目成果", created.stderr)
        self.assertFalse(self.output.exists())

    def test_invalid_existing_output_setting_never_writes_to_random_relative_path(self):
        self.assertEqual(self.initialize(specify=False).returncode, 0)
        path = self.install / "config/workspace.json"
        cfg = json.loads(path.read_text("utf8"))
        cfg["output_root"] = "../relative"
        path.write_text(json.dumps(cfg, ensure_ascii=False), encoding="utf8")
        new = self.run_script("studio.py", "--root", self.install, "new",
                              "--id", "wrong-001", "--title", "不能建立")
        self.assertEqual(new.returncode, 2)
        self.assertFalse((self.install / "outputs" / "wrong-001").exists())
        self.assertFalse((self.install.parent / "relative" / "wrong-001").exists())

    @unittest.skipUnless(os.name == "nt" and shutil.which("powershell.exe"),
                         "Requires Windows PowerShell 5.1")
    def test_windows_setup_rejects_nested_output_before_downloading(self):
        """A failed first-run choice must not install runtimes or create directories."""
        nested = self.knowledge / "clips"
        command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy",
                   "Bypass", "-File", str(SOURCE / "SETUP-WINDOWS.ps1"),
                   "-InstallRoot", str(self.install), "-KnowledgeRoot", str(self.knowledge),
                   "-OutputRoot", str(nested), "-SkipGit", "-SkipFfmpeg"]
        result = subprocess.run(command, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=15)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.install.exists())
        self.assertFalse(self.knowledge.exists())
        self.assertFalse(nested.exists())

    def test_offline_smoke_cannot_escape_configured_project_root(self):
        self.assertEqual(self.initialize().returncode, 0)
        attempt = self.run_script("offline_smoke.py", "--install-root", self.install,
                                  "--output-id", "../escaped")
        self.assertNotEqual(attempt.returncode, 0)
        self.assertFalse((self.output.parent / "escaped").exists())

    def test_export_rejects_destination_inside_separate_output_root(self):
        self.assertEqual(self.initialize().returncode, 0)
        p = self.run_script("export_assets.py", "--install-root", self.install,
                            "--destination", self.output / "accidental-recursive.zip")
        self.assertNotEqual(p.returncode, 0)
        self.assertFalse((self.output / "accidental-recursive.zip").exists())


if __name__ == "__main__":
    unittest.main()
