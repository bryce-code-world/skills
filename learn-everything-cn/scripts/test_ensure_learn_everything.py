import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("ensure_learn_everything.py")


class EnsureLearnEverythingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.dest_root = self.root / "skills"
        self.lock_path = self.root / "dependency-lock.json"

    @staticmethod
    def sample_files():
        return {
            "SKILL.md": b"---\nname: learn-everything\ndescription: test\n---\n",
            "agents/openai.yaml": b'interface:\n  display_name: "Learn Everything"\n',
            "references/practice-and-mastery.md": b"# Practice\n",
            "references/session-formats.md": b"# Sessions\n",
            "LICENSE.upstream": b"MIT License\n",
        }

    def write_source(self, files):
        entries = []
        for relative_path, content in files.items():
            source_file = self.source / relative_path
            source_file.parent.mkdir(parents=True, exist_ok=True)
            source_file.write_bytes(content)
            entries.append(
                {
                    "path": relative_path,
                    "sha256": hashlib.sha256(content).hexdigest(),
                    **(
                        {
                            "required_for_existing": False,
                            "bundled_path": "upstream-license.txt",
                        }
                        if relative_path == "LICENSE.upstream"
                        else {}
                    ),
                }
            )
        if "LICENSE.upstream" in files:
            (self.root / "upstream-license.txt").write_bytes(files["LICENSE.upstream"])
        self.lock_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "dependency": "learn-everything",
                    "repository": "example/repository",
                    "ref": "fixed-ref",
                    "source_path": "skill",
                    "files": entries,
                }
            ),
            encoding="utf-8",
        )

    def run_installer(self, source_base=None, *, explicit_dest=True, env=None):
        command = [
            sys.executable,
            "-X",
            "utf8",
            str(SCRIPT),
            "--lock",
            str(self.lock_path),
            "--source-base",
            source_base or self.source.as_uri() + "/",
            "--json",
        ]
        if explicit_dest:
            command[6:6] = ["--dest-root", str(self.dest_root)]
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
        )

    def test_installs_missing_dependency_and_returns_installed_path(self):
        self.write_source(self.sample_files())

        result = self.run_installer()

        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        target = self.dest_root / "learn-everything"
        self.assertEqual(payload["status"], "installed")
        self.assertEqual(Path(payload["path"]), target.resolve())
        self.assertEqual((target / "SKILL.md").read_text(encoding="utf-8"), "---\nname: learn-everything\ndescription: test\n---\n")
        metadata = json.loads(
            (target / ".learn-everything-install.json").read_text(encoding="utf-8")
        )
        self.assertEqual(metadata["dependency"], "learn-everything")
        self.assertEqual(
            {entry["path"]: entry["sha256"] for entry in metadata["files"]},
            {
                entry["path"]: entry["sha256"]
                for entry in json.loads(
                    self.lock_path.read_text(encoding="utf-8")
                )["files"]
            },
        )

    def test_exact_existing_dependency_is_ready_without_network(self):
        files = self.sample_files()
        self.write_source(files)
        target = self.dest_root / "learn-everything"
        for relative_path, content in files.items():
            destination = target / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)

        result = self.run_installer("file:///source-that-does-not-exist/")

        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "ready")
        self.assertEqual(Path(payload["path"]), target.resolve())
        self.assertTrue((target / ".learn-everything-install.json").is_file())

    def test_uses_existing_codex_home_dependency_without_duplicate_install(self):
        files = self.sample_files()
        self.write_source(files)
        codex_home = self.root / "codex-home"
        target = codex_home / "skills" / "learn-everything"
        for relative_path, content in files.items():
            destination = target / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        isolated_home = self.root / "user-home"
        isolated_home.mkdir()
        env = os.environ.copy()
        env.update(
            {
                "CODEX_HOME": str(codex_home),
                "HOME": str(isolated_home),
                "USERPROFILE": str(isolated_home),
            }
        )

        result = self.run_installer(
            "file:///source-that-does-not-exist/",
            explicit_dest=False,
            env=env,
        )

        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "ready")
        self.assertEqual(Path(payload["path"]), target.resolve())
        self.assertFalse(
            (isolated_home / ".agents" / "skills" / "learn-everything").exists()
        )

    def test_conflicting_dependency_is_preserved(self):
        self.write_source(self.sample_files())
        target = self.dest_root / "learn-everything"
        target.mkdir(parents=True)
        conflicting_content = b"user-managed content\n"
        (target / "SKILL.md").write_bytes(conflicting_content)

        result = self.run_installer()

        self.assertEqual(result.returncode, 3, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "conflict")
        self.assertEqual((target / "SKILL.md").read_bytes(), conflicting_content)

    def test_hash_failure_leaves_no_target_or_install_temp(self):
        files = self.sample_files()
        self.write_source(files)
        (self.source / "SKILL.md").write_bytes(b"tampered\n")

        result = self.run_installer()

        self.assertEqual(result.returncode, 4, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "verification_failed")
        self.assertFalse((self.dest_root / "learn-everything").exists())
        leftovers = list(self.dest_root.glob(".learn-everything-*"))
        self.assertEqual(leftovers, [])

    def test_repairs_exact_manual_install_without_network(self):
        files = self.sample_files()
        self.write_source(files)
        target = self.dest_root / "learn-everything"
        for relative_path, content in files.items():
            if relative_path == "LICENSE.upstream":
                continue
            destination = target / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)

        result = self.run_installer("file:///source-that-does-not-exist/")

        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "ready")
        self.assertEqual(
            (target / "LICENSE.upstream").read_bytes(),
            files["LICENSE.upstream"],
        )

    def test_rejects_locked_skill_with_wrong_frontmatter_name(self):
        files = self.sample_files()
        files["SKILL.md"] = b"---\nname: another-skill\ndescription: test\n---\n"
        self.write_source(files)

        result = self.run_installer()

        self.assertEqual(result.returncode, 4, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "verification_failed")
        self.assertFalse((self.dest_root / "learn-everything").exists())

    def test_installs_file_from_distinct_source_path(self):
        files = self.sample_files()
        self.write_source(files)
        lock = json.loads(self.lock_path.read_text(encoding="utf-8"))
        license_entry = next(
            entry for entry in lock["files"] if entry["path"] == "LICENSE.upstream"
        )
        license_entry["source"] = "LICENSE"
        self.lock_path.write_text(json.dumps(lock), encoding="utf-8")
        (self.source / "LICENSE.upstream").rename(self.source / "LICENSE")

        result = self.run_installer()

        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        target = self.dest_root / "learn-everything"
        self.assertEqual(
            (target / "LICENSE.upstream").read_bytes(),
            files["LICENSE.upstream"],
        )

    def test_source_failure_leaves_no_target_or_install_temp(self):
        self.write_source(self.sample_files())

        result = self.run_installer("file:///source-that-does-not-exist/")

        self.assertEqual(result.returncode, 2, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "error")
        self.assertFalse((self.dest_root / "learn-everything").exists())
        leftovers = list(self.dest_root.glob(".learn-everything-*"))
        self.assertEqual(leftovers, [])

    def test_ready_dependency_does_not_rewrite_matching_metadata(self):
        self.write_source(self.sample_files())
        first = self.run_installer()
        self.assertEqual(first.returncode, 0, first.stderr or first.stdout)
        metadata = self.dest_root / "learn-everything" / ".learn-everything-install.json"
        first_mtime = metadata.stat().st_mtime_ns
        time.sleep(0.02)

        second = self.run_installer("file:///source-that-does-not-exist/")

        self.assertEqual(second.returncode, 0, second.stderr or second.stdout)
        self.assertEqual(json.loads(second.stdout)["status"], "ready")
        self.assertEqual(metadata.stat().st_mtime_ns, first_mtime)


if __name__ == "__main__":
    unittest.main()
