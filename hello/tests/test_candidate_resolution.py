import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
SKILL = ROOT / "skills" / "bryce-skills" / "hello"
CANDIDATE_ID = "C-20260831T000000Z-1"


def bash_available() -> bool:
    try:
        return subprocess.run(["bash", "-c", "exit 0"], capture_output=True).returncode == 0
    except OSError:
        return False


def make_target(root: Path) -> None:
    def write(path: Path, content: str) -> None:
        path.write_bytes(content.replace("\r\n", "\n").encode("utf-8"))

    for name in ("原始访谈", "来源", "权威", "派生", "历史版本", ".backups", ".trash"):
        (root / name).mkdir(parents=True, exist_ok=True)
    write(root / "权威" / "声明索引.json", '{"entries": []}\n')
    write(root / "README.md", "# 个人资料包\n")
    write(root / "个人全景档案.md", "# 个人全景档案\n")
    write(root / "主题覆盖矩阵.md", "# 主题覆盖矩阵\n")
    write(root / "资料索引.md", "# 资料索引\n")
    write(root / "迭代日志.md", "# 迭代日志\n")
    write(root / "访谈进度.md", "# 访谈进度\n\n## 已覆盖主题\n\n## 待补充主题\n\n## 暂不收集\n\n## 下次问题\n")
    write(
        root / "待确认信息.md",
        f"# 待确认信息\n\n## {CANDIDATE_ID}\n\n- 暂存时间：2026-08-31T00:00:00Z\n- 类型：历史资料\n- 来源：测试\n- 状态：待确认\n\n历史候选正文。\n",
    )
    write(
        root / ".hello-state",
        "\n".join(
            [
                "layout=target",
                "layout_version=1",
                "schema_version=3",
                "migration_id=test-migration",
                "package_id=test-package",
                "subject_id=test-subject",
                "profile_version=1",
                "progress_version=1",
                "capture_mode=explicit",
                "created_at=2026-08-31T00:00:00Z",
                "updated_at=2026-08-31T00:00:00Z",
                "last_confirmed_at=",
                "next_review_at=",
                "review_stage=baseline",
                "last_interview_at=",
                "last_session_id=",
                "last_turn_id=",
                "last_capture_disclosed_at=",
                "last_capture_disclosed_mode=",
            ]
        )
        + "\n",
    )
    write(
        root / "manifest.json",
        json.dumps(
            {
                "layout": "target",
                "layout_version": 1,
                "schema_version": 3,
                "migration_id": "test-migration",
                "package_id": "test-package",
                "subject_id": "test-subject",
                "owner": "local-owner",
                "audience": "owner-and-authorized-ai",
            }
        )
        + "\n",
    )


class CandidateResolutionTests(unittest.TestCase):
    def _assert_resolution(self, command):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "target"
            make_target(root)
            result = subprocess.run(
                command + [
                    "resolve-candidate",
                    "--root",
                    str(root),
                    "--id",
                    CANDIDATE_ID,
                    "--disposition",
                    "merged",
                    "--reason",
                    "合并为历史旁证",
                    "--merge-target",
                    "MIG-声-0016",
                    "--confirmed",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["command"], "resolve-candidate")
            self.assertEqual(payload["disposition"], "merged")
            self.assertFalse(f"## {CANDIDATE_ID}" in (root / "待确认信息.md").read_text(encoding="utf-8"))
            self.assertTrue((root / ".trash" / "candidates" / f"{CANDIDATE_ID}.md").is_file())
            index = json.loads((root / "候选处置索引.json").read_text(encoding="utf-8"))
            self.assertEqual(index["entries"][0]["candidate_id"], CANDIDATE_ID)
            self.assertEqual(index["entries"][0]["disposition"], "merged")

    def test_python_resolve_candidate_archives_and_records_disposition(self):
        self._assert_resolution(["python", str(SKILL / "scripts" / "profile_store.py")])

    def test_powershell_resolve_candidate_archives_and_records_disposition(self):
        self._assert_resolution(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(SKILL / "scripts" / "profile_store.ps1"),
            ]
        )

    @unittest.skipUnless(bash_available(), "bash is required for the POSIX adapter test")
    def test_shell_resolve_candidate_archives_and_records_disposition(self):
        self._assert_resolution(["bash", str(SKILL / "scripts" / "profile_store.sh")])


if __name__ == "__main__":
    unittest.main()
