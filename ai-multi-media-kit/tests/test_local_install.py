"""Checks durable workspace lookup across new processes and unrelated working directories."""
from __future__ import annotations

import json
import os
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
        shutil.copytree(SOURCE, self.skill, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "local-install.json"))
        self.workspace = self.base / "toolspace"
        self.knowledge = self.base / "知识 库"
        self.other_cwd = self.base / "unrelated project"
        self.other_cwd.mkdir()
        # Keep per-user shared locator writes inside this disposable test fixture.
        self.env = os.environ.copy()
        self.env['LOCALAPPDATA'] = str(self.base / 'Local AppData')
        self.env['XDG_CONFIG_HOME'] = str(self.base / 'xdg config')
        config_home = Path(self.env['LOCALAPPDATA'] if os.name == 'nt' else self.env['XDG_CONFIG_HOME'])
        self.shared_registry = config_home / 'ai-multi-media-kit' / 'local-install.json'

    def run_script(self, script, *args, skill=None):
        source_skill = skill or self.skill
        return subprocess.run(
            [sys.executable, '-X', 'utf8', str(source_skill / 'scripts' / script), *map(str, args)],
            cwd=self.other_cwd, env=self.env, capture_output=True, text=True, encoding='utf-8',
            errors='replace', timeout=30
        )

    def initialize(self, workspace=None, knowledge=None, *, new_workspace=False):
        args=["--install-root", workspace or self.workspace,
              "--knowledge-root", knowledge or self.knowledge, "--remember"]
        if new_workspace:args.append("--new-workspace")
        return self.run_script("init_workspace.py", *args)

    def test_init_remembers_default_for_new_process_and_no_global_path(self):
        first = self.initialize()
        self.assertEqual(first.returncode, 0, first.stderr)
        index = self.skill / "config" / "local-install.json"
        self.assertTrue(index.is_file())
        self.assertTrue(self.shared_registry.is_file())
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
        p = self.initialize(newer, newer_k, new_workspace=True)
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

    def test_two_agent_installations_share_same_workspace_via_user_config(self):
        """Removing per-Skill discovery must not force a second agent to reinitialize."""
        self.assertEqual(self.initialize().returncode, 0)
        second_skill = self.base / 'second Agent vendor skill'
        shutil.copytree(SOURCE, second_skill, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'local-install.json'))
        self.assertFalse((second_skill / 'config' / 'local-install.json').exists())
        found = self.run_script('workspace_locator.py', 'show', skill=second_skill)
        self.assertEqual(found.returncode, 0, found.stderr)
        self.assertEqual(json.loads(found.stdout)['install_root'], str(self.workspace.resolve()))
        self.assertEqual(json.loads(found.stdout)['index_source'], 'shared-user-config')
        self.assertFalse((second_skill / 'config' / 'local-install.json').exists())

    def test_explicit_rebind_in_one_agent_is_visible_to_every_other_agent(self):
        """Register must supersede stale per-agent cache without changing old workspace."""
        self.assertEqual(self.initialize().returncode, 0)
        second_skill = self.base / 'another agent'
        shutil.copytree(SOURCE, second_skill, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'local-install.json'))
        newer, newer_k = self.base / 'new tools', self.base / 'new knowledge'
        new_init = self.run_script('init_workspace.py', '--install-root', newer,
                                   '--knowledge-root', newer_k, '--new-workspace')
        self.assertEqual(new_init.returncode, 0, new_init.stderr)
        changed = self.run_script('workspace_locator.py', 'register', '--install-root', newer, skill=second_skill)
        self.assertEqual(changed.returncode, 0, changed.stderr)
        primary = self.run_script('workspace_locator.py', 'show')
        self.assertEqual(primary.returncode, 0, primary.stderr)
        self.assertEqual(json.loads(primary.stdout)['install_root'], str(newer.resolve()))
        self.assertTrue((self.workspace / 'config' / 'workspace.json').is_file())

    def test_legacy_per_agent_record_still_readable_when_shared_absent(self):
        """Old V0.3 users must recover an existing runtime without a reinstall."""
        self.assertEqual(self.initialize().returncode, 0)
        self.shared_registry.unlink()
        before = (self.skill / 'config' / 'local-install.json').read_bytes()
        result = self.run_script('workspace_locator.py', 'show')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['index_source'], 'legacy-skill-local')
        self.assertFalse(self.shared_registry.exists())
        self.assertEqual((self.skill / 'config' / 'local-install.json').read_bytes(), before)
        migrated = self.run_script('workspace_locator.py', 'register', '--install-root', self.workspace)
        self.assertEqual(migrated.returncode, 0, migrated.stderr)
        self.assertTrue(self.shared_registry.is_file())

    def test_invalid_shared_record_never_falls_back_silently(self):
        """A corrupt shared default must not silently select a different agent's cache."""
        self.assertEqual(self.initialize().returncode, 0)
        self.shared_registry.write_text('{invalid-json', encoding='utf8')
        result = self.run_script('workspace_locator.py', 'show')
        self.assertEqual(result.returncode, 2)
        self.assertIn('本机安装记录', result.stderr)
        self.assertTrue((self.skill / 'config' / 'local-install.json').is_file())

    def test_doctor_does_not_assume_codex_cli_is_host(self):
        """A Claude or other host must not be reported as missing Codex."""
        self.assertEqual(self.initialize().returncode, 0)
        output = self.base / "doctor.json"
        proc = self.run_script("doctor.py", "--install-root", self.workspace,
                               "--scope", "all", "--json-output", output)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        checks = json.loads(output.read_text("utf8"))["checks"]
        self.assertFalse(any("Codex" in c["name"] for c in checks))
        self.assertTrue(any(c["name"] == "内容工作流 CLI" for c in checks))

    def test_repeated_setup_is_read_only_and_reports_reuse(self):
        self.assertEqual(self.initialize().returncode, 0)
        before_config=(self.workspace/'config/workspace.json').read_bytes()
        before_record=self.shared_registry.read_bytes()
        before_brand=(self.knowledge/'brand.md').stat().st_mtime_ns
        followup=self.initialize()
        self.assertEqual(followup.returncode, 0, followup.stderr)
        self.assertIn('REUSE_EXISTING_WORKSPACE', followup.stdout)
        self.assertEqual((self.workspace/'config/workspace.json').read_bytes(),before_config)
        self.assertEqual(self.shared_registry.read_bytes(),before_record)
        self.assertEqual((self.knowledge/'brand.md').stat().st_mtime_ns,before_brand)

    def test_second_agent_with_matching_paths_reuses_without_local_reconfiguration(self):
        self.assertEqual(self.initialize().returncode, 0)
        second = self.base / 'second skill package'
        shutil.copytree(SOURCE, second, ignore=shutil.ignore_patterns('__pycache__','*.pyc','local-install.json'))
        before_config=(self.workspace/'config/workspace.json').read_bytes()
        before_shared=self.shared_registry.read_bytes()
        probe=self.run_script('init_workspace.py','--install-root',self.workspace,
                              '--knowledge-root',self.knowledge,'--remember',skill=second)
        self.assertEqual(probe.returncode,0,probe.stderr)
        self.assertIn('REUSE_EXISTING_WORKSPACE',probe.stdout)
        self.assertFalse((second/'config/local-install.json').exists())
        self.assertEqual((self.workspace/'config/workspace.json').read_bytes(),before_config)
        self.assertEqual(self.shared_registry.read_bytes(),before_shared)

    def test_new_agent_cannot_reinitialize_a_second_workspace_by_default(self):
        self.assertEqual(self.initialize().returncode, 0)
        new_tools=self.base/'new agent duplicate'
        new_kb=self.base/'new knowledge duplicate'
        second=self.base/'vendor two'
        shutil.copytree(SOURCE,second,ignore=shutil.ignore_patterns('__pycache__','*.pyc','local-install.json'))
        before=self.shared_registry.read_bytes()
        denied=self.run_script('init_workspace.py','--install-root',new_tools,
                               '--knowledge-root',new_kb,'--remember',skill=second)
        self.assertEqual(denied.returncode, 2, denied.stderr)
        self.assertIn('已有', denied.stderr)
        self.assertFalse(new_tools.exists())
        self.assertFalse(new_kb.exists())
        self.assertEqual(self.shared_registry.read_bytes(),before)

    def test_corrupt_shared_pointer_blocks_default_new_workspace(self):
        self.assertEqual(self.initialize().returncode, 0)
        self.shared_registry.write_text('{invalid json',encoding='utf8')
        target=self.base/'hidden-second-workspace'
        denied=self.run_script('init_workspace.py','--install-root',target,
                               '--knowledge-root',self.base/'second-knowledge')
        self.assertEqual(denied.returncode,2)
        self.assertFalse(target.exists())
        self.assertIn('本机安装记录',denied.stderr)

    def test_show_validates_shared_output_root_and_requested_workspace(self):
        self.assertEqual(self.initialize().returncode,0)
        cfg=json.loads((self.workspace/'config/workspace.json').read_text('utf8'))
        out=Path(cfg['output_root']).resolve()
        same=self.run_script('workspace_locator.py','show','--install-root',self.workspace)
        self.assertEqual(same.returncode,0,same.stderr)
        self.assertEqual(json.loads(same.stdout)['output_root'],str(out))
        wrong=self.run_script('workspace_locator.py','show','--install-root',self.base/'other')
        self.assertEqual(wrong.returncode,2)
        self.assertIn('不一致',wrong.stderr)

    def test_existing_workspace_inspect_recovers_without_any_locator_or_install(self):
        first=self.run_script('init_workspace.py','--install-root',self.workspace,
                              '--knowledge-root',self.knowledge)
        self.assertEqual(first.returncode,0,first.stderr)
        self.assertFalse(self.shared_registry.exists())
        result=self.run_script('workspace_locator.py','inspect','--install-root',self.workspace)
        self.assertEqual(result.returncode,0,result.stderr)
        data=json.loads(result.stdout)
        self.assertEqual(data['install_root'],str(self.workspace.resolve()))
        self.assertEqual(data['knowledge_root'],str(self.knowledge.resolve()))
        self.assertEqual(data['output_root'],str((self.workspace/'outputs').resolve()))
        self.assertFalse(self.shared_registry.exists())
        mismatch=self.run_script('workspace_locator.py','inspect','--install-root',self.workspace,
                                 '--knowledge-root',self.base/'wrong')
        self.assertEqual(mismatch.returncode,2)
        self.assertFalse((self.base/'wrong').exists())

    def test_registry_is_explicitly_ignored_by_gitignore(self):
        gitignore = (self.skill / ".gitignore").read_text("utf8")
        self.assertIn("config/local-install.json", gitignore)


if __name__ == "__main__":
    unittest.main()
