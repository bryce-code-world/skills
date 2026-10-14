"""Checks durable workspace lookup across new processes and unrelated working directories."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]


class LocalInstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.skill = self.base / "installed skill with spaces"
        shutil.copytree(SOURCE, self.skill, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        self.workspace = self.base / "toolspace"
        self.knowledge = self.base / "知识 库"
        self.other_cwd = self.base / "unrelated project"
        self.other_cwd.mkdir()

    def run_script(self, script, *args):
        return subprocess.run(
            [sys.executable, "-X", "utf8", str(self.skill / "scripts" / script), *map(str, args)],
            cwd=self.other_cwd, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=30
        )

    def initialize(self, workspace=None, knowledge=None):
        return self.run_script("init_workspace.py", "--install-root", workspace or self.workspace,
                               "--knowledge-root", knowledge or self.knowledge, "--remember")

    def test_init_remembers_default_for_new_process_and_no_global_path(self):
        first = self.initialize()
        self.assertEqual(first.returncode, 0, first.stderr)
        index = self.skill / "config" / "local-install.json"
        self.assertTrue(index.is_file())
        info = json.loads(index.read_text(encoding="utf8"))
        self.assertEqual(info["install_root"], str(self.workspace.resolve()))
        self.assertEqual(info["knowledge_root"], str(self.knowledge.resolve()))
        self.assertFalse((self.workspace / "config" / "local-install.json").exists())
        located = self.run_script("workspace_locator.py", "show")
        self.assertEqual(located.returncode, 0, located.stderr)
        self.assertEqual(json.loads(located.stdout)["install_root"], str(self.workspace.resolve()))
        self.assertIn("RUN-STUDIO-WINDOWS.ps1", located.stdout)
        self.assertEqual(index.read_text("utf8"), index.read_text("utf8"))

    def test_reinitialization_is_idempotent_and_preserves_user_data(self):
        self.assertEqual(self.initialize().returncode, 0)
        index = self.skill / "config" / "local-install.json"
        original = index.read_bytes()
        marker = self.knowledge / "brand.md"
        marker.write_text("品牌文件不应被覆盖", encoding="utf8")
        p = self.initialize()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(original, index.read_bytes())
        self.assertEqual(marker.read_text("utf8"), "品牌文件不应被覆盖")

    def test_explicit_new_workspace_switches_default_without_altering_previous(self):
        self.assertEqual(self.initialize().returncode, 0)
        newer = self.base / "Another tools"
        newer_k = self.base / "Other knowledge"
        p = self.initialize(newer, newer_k)
        self.assertEqual(p.returncode, 0, p.stderr)
        index = json.loads((self.skill / "config" / "local-install.json").read_text("utf8"))
        self.assertEqual(index["install_root"], str(newer.resolve()))
        self.assertTrue((self.workspace / "config" / "workspace.json").exists())
        self.assertTrue((newer / "config" / "workspace.json").exists())
        self.assertFalse((newer / "config" / "local-install.json").exists())

    def test_stale_workspace_pointer_fails_without_guessing_or_reinstall(self):
        self.assertEqual(self.initialize().returncode, 0)
        cfg = self.workspace / "config" / "workspace.json"
        cfg.rename(self.workspace / "config" / "workspace.hidden.json")
        p = self.run_script("workspace_locator.py", "show")
        self.assertEqual(p.returncode, 2)
        self.assertIn("工作区", p.stderr)
        self.assertTrue((self.skill / "config" / "local-install.json").is_file())

    def test_failed_init_does_not_change_saved_locator(self):
        self.assertEqual(self.initialize().returncode, 0)
        index = self.skill / "config" / "local-install.json"
        before = index.read_bytes()
        bad = self.initialize(self.workspace, self.base / "wrong location")
        self.assertEqual(bad.returncode, 2)
        self.assertEqual(index.read_bytes(), before)
        self.assertFalse((self.base / "wrong location").exists())

    def test_locator_register_only_existing_matching_workspace(self):
        target = self.base / "not initialized"
        fail = self.run_script("workspace_locator.py", "register", "--install-root", target)
        self.assertEqual(fail.returncode, 2)
        self.assertFalse((self.skill / "config" / "local-install.json").exists())
        self.assertEqual(self.initialize().returncode, 0)
        ok = self.run_script("workspace_locator.py", "register", "--install-root", self.workspace)
        self.assertEqual(ok.returncode, 0, ok.stderr)

    def test_ordinary_scaffolding_does_not_write_an_unrequested_global_pointer(self):
        index = self.skill / "config" / "local-install.json"
        before = index.read_bytes() if index.exists() else None
        p = self.run_script("init_workspace.py", "--install-root", self.workspace,
                            "--knowledge-root", self.knowledge)
        self.assertEqual(p.returncode, 0, p.stderr)
        after = index.read_bytes() if index.exists() else None
        self.assertEqual(after, before)

    def test_registry_is_explicitly_ignored_by_gitignore(self):
        gitignore = (self.skill / ".gitignore").read_text("utf8")
        self.assertIn("config/local-install.json", gitignore)


if __name__ == "__main__":
    unittest.main()
