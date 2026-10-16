"""Automatic workflow regression: all fixtures local; no network or real publishing."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import studio  # noqa: E402
import installer  # noqa: E402
import materials  # noqa: E402
import configure_mcp  # noqa: E402


def call(script, root, *args):
    return subprocess.run(
        [sys.executable, "-X", "utf8", str(ROOT / "scripts" / script), "--root", str(root), *map(str, args)],
        text=True, capture_output=True, encoding="utf-8", errors="replace", timeout=40,
    )


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


class AutomaticWorkflowTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name)
        self.ffmpeg = os.environ.get('AI_MEDIA_TEST_FFMPEG') or shutil.which('ffmpeg')
        self.ffprobe = os.environ.get('AI_MEDIA_TEST_FFPROBE') or shutil.which('ffprobe')
        overrides={'LOCALAPPDATA':str(base/'user-config'), 'XDG_CONFIG_HOME':str(base/'xdg-config')}
        if self.ffmpeg and self.ffprobe:
            overrides['PATH']=str(Path(self.ffmpeg).parent)+os.pathsep+os.environ.get('PATH','')
        local=patch.dict(os.environ,overrides)
        local.start(); self.addCleanup(local.stop)
        self.root, self.knowledge = base / "tool", base / "knowledge"
        init = subprocess.run(
            [sys.executable, "-X", "utf8", str(ROOT / "scripts" / "init_workspace.py"),
             "--install-root", str(self.root), "--knowledge-root", str(self.knowledge)],
            capture_output=True, text=True, timeout=40,
        )
        self.assertEqual(init.returncode, 0, init.stderr)
        self.id = "demo-auto"
        result = self.studio("new", "--id", self.id, "--title", "自动视频制作")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.folder = self.root / "outputs" / self.id
        self._script()

    def studio(self, *args):
        return call("studio.py", self.root, *args)

    def _script(self):
        platforms = {p: {"title": p + " 的标题", "description": "原创测试", "tags": []}
                     for p in studio.PLATFORMS}
        write(self.folder / "script.json", {
            "content_id": self.id, "title": "自动视频制作", "narration": "这是 AI 自动制作的原创测试视频脚本。",
            "duration_seconds": 8, "shots": [{"seconds": 8, "visual": "原创画面", "voiceover": "口播"}],
            "platforms": platforms, "article_markdown": "# 自动化\n原创测试",
        })
        write(self.folder / "review.json", {
            "result": "PASS", "checks": [{"rule": "事实", "result": "PASS", "reason": "原创"}],
            "facts_to_verify": [], "issues": [],
            "script_sha256": studio.filehash(self.folder / "script.json"),
            "review_standard_sha256": studio.filehash(self.knowledge / "review-rules.md"),
        })

    def _video(self):
        if not self.ffmpeg or not self.ffprobe:
            self.skipTest('FFmpeg needed for actual video state-machine tests')
        video = self.folder / "video" / "master.mp4"
        video.parent.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run([self.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=navy:s=160x280:r=12:d=8",
            "-f", "lavfi", "-i", "sine=frequency=340:duration=8:sample_rate=22050",
            "-map", "0:v", "-map", "1:a", "-t", "8", "-c:v", "libx264",
            "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "aac", str(video)],
            capture_output=True, text=True, timeout=45)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        write(self.folder / "video" / "render.json", {
            "engine": "import",
            "video_sha256": studio.filehash(video),
            "script_sha256": studio.filehash(self.folder / "script.json"),
        })
        write(self.folder / "video" / "review.json", {
            "result": "PASS", "checks": [{"rule": "视听检查", "result": "PASS", "reason": "测试夹具"}],
            "facts_to_verify": [], "issues": [],
            "video_sha256": studio.filehash(video),
            "script_sha256": studio.filehash(self.folder / "script.json"),
            "review_standard_sha256": studio.filehash(self.knowledge / "review-rules.md"),
        })

    def test_pass_review_allows_render_without_human_approval(self):
        status = json.loads(self.studio("check", "--id", self.id).stdout)
        self.assertEqual(status["script_ready"], "valid")
        clip = self.root / "original.mp4"
        clip.write_bytes(b"placeholder; dry-run never decodes")
        material = call("materials.py", self.root, "add-file", "--path", clip,
                        "--rights", "owned", "--license-note", "原创测试")
        self.assertEqual(material.returncode, 0, material.stderr)
        mid = json.loads(material.stdout)["id"]
        render = self.studio("render", "--id", self.id, "--material-ids", mid,
                             "--rights-confirmed", "--dry-run")
        self.assertEqual(render.returncode, 0, render.stderr)
        self.assertFalse((self.folder / "approvals").exists())

    def test_pass_review_cannot_bypass_script_structure(self):
        script_file = self.folder / "script.json"
        content = json.loads(script_file.read_text("utf-8"))
        content["platforms"]["zhihu"]["title"] = ""
        write(script_file, content)
        review_file = self.folder / "review.json"
        review = json.loads(review_file.read_text("utf-8"))
        review["script_sha256"] = studio.filehash(script_file)
        write(review_file, review)
        with self.assertRaisesRegex(ValueError, "zhihu"):
            studio.ensure_reviewed_script(self.folder, self.knowledge)

    def test_bad_or_stale_ai_review_blocks_work(self):
        rpath = self.folder / "review.json"
        data = json.loads(rpath.read_text("utf-8"))
        data["facts_to_verify"] = ["未核实"]
        write(rpath, data)
        self.assertIn("待核", json.loads(self.studio("check", "--id", self.id).stdout)["script_ready"])
        data["facts_to_verify"] = []
        write(rpath, data)
        script_path = self.folder / "script.json"
        script = json.loads(script_path.read_text("utf-8"))
        script["narration"] += "更新"
        write(script_path, script)
        self.assertIn("脚本内容发生变化", json.loads(self.studio("check", "--id", self.id).stdout)["script_ready"])

    def test_video_ai_review_is_required_and_revision_bound(self):
        self._video()
        self.assertEqual(self.studio("package", "--id", self.id).returncode, 0)
        self.assertFalse((self.folder / "approvals").exists())
        (self.folder / "video" / "master.mp4").write_bytes(b"changed")
        fail = self.studio("package", "--id", self.id, "--replace")
        self.assertEqual(fail.returncode, 2)
        self.assertIn("成片", fail.stderr)

    def test_publish_scope_only_initial_task_exact_account(self):
        self._video()
        self.assertEqual(self.studio("package", "--id", self.id, "--platform", "douyin").returncode, 0)
        unscoped = self.studio("publish", "--id", self.id, "--platform", "douyin",
                               "--account", "main", "--execute")
        self.assertEqual(unscoped.returncode, 2)
        self.assertIn("初始任务", unscoped.stderr)

        scoped = "authorized-upload"
        created = self.studio("new", "--id", scoped, "--title", "明确授权发布",
                              "--publish-target", "douyin:main",
                              "--task-ref", "chat:user-message-10")
        self.assertEqual(created.returncode, 0, created.stderr)
        meta = json.loads((self.root / "outputs" / scoped / "content.json").read_text("utf-8"))
        self.assertEqual(meta["publish_targets"], {"douyin": "main"})
        self.assertEqual(meta["task_ref"], "chat:user-message-10")
        self.assertEqual(self.studio("new", "--id", "wrong", "--title", "无效账号",
                                      "--publish-target", "douyin:*").returncode, 2)

        # Same script/review/video fixture, but explicitly authorized task ID.
        authorized_dir = self.root / "outputs" / scoped
        for rel in ("script.json", "review.json", "video/master.mp4", "video/render.json", "video/review.json"):
            value = (self.folder / rel).read_bytes()
            dest = authorized_dir / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(value)
        script_path = authorized_dir / "script.json"
        script_data = json.loads(script_path.read_text("utf-8"))
        script_data["content_id"] = scoped
        write(script_path, script_data)
        r = json.loads((authorized_dir / "review.json").read_text("utf-8"))
        r["script_sha256"] = studio.filehash(script_path)
        write(authorized_dir / "review.json", r)
        for name in ("render.json", "review.json"):
            p = authorized_dir / "video" / name
            data = json.loads(p.read_text("utf-8"))
            data["script_sha256"] = studio.filehash(script_path)
            write(p, data)
        self.assertEqual(self.studio("package", "--id", scoped, "--platform", "douyin").returncode, 0)
        wrong = self.studio("publish", "--id", scoped, "--platform", "douyin",
                            "--account", "other", "--execute")
        self.assertEqual(wrong.returncode, 2)
        self.assertIn("初始任务", wrong.stderr)

        # Simulate the existing external uploader without actually posting anything.
        fake_cli = self.root / "sau.exe"
        fake_cli.write_bytes(b"test-stub")
        actual_run = subprocess.run
        def run_except_upload(cmd, *args, **kwargs):
            if Path(str(cmd[0])) == fake_cli:
                return subprocess.CompletedProcess(cmd, 0, "", "")
            return actual_run(cmd, *args, **kwargs)
        with patch.object(studio, "sau_binary", return_value=fake_cli), patch.object(
            studio.subprocess, "run", side_effect=run_except_upload
        ) as run:
            args = type("Args", (), {
                "root": str(self.root), "id": scoped, "platform": "douyin",
                "account": "main", "tid": None, "execute": True
            })()
            studio.cmd_publish(args)
            self.assertEqual(sum(1 for call in run.call_args_list if Path(str(call.args[0][0])) == fake_cli), 1)
        ledger = json.loads((authorized_dir / "publish-ledger.json").read_text("utf-8"))
        self.assertEqual(ledger["platforms"]["douyin"]["state"], "submitted_unknown")
        self.assertEqual(self.studio("publish", "--id", scoped, "--platform", "douyin",
                                     "--account", "main", "--execute").returncode, 2)

    def test_free_tool_install_is_noninteractive_after_execute_flag(self):
        # A fake retriever represents only the already-validated allowlisted source.
        with patch.object(installer, "retrieve") as retrieve, patch(
                "builtins.input", side_effect=AssertionError("unexpected installation prompt")
        ), patch.object(sys, "argv", ["installer.py", "--root", str(self.root),
                                      "--component", "marketing", "--install"]):
            self.assertEqual(installer.main(), 0)
            retrieve.assert_called_once()

    def test_free_material_fetch_does_not_prompt_for_stage_approval(self):
        mpt = self.root / "tools" / "MoneyPrinterTurbo"
        exe = mpt / ".venv" / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
        exe.parent.mkdir(parents=True, exist_ok=True)
        exe.write_bytes(b"test dummy binary")
        (mpt / "cli.py").write_text("# test fixture", encoding="utf-8")
        args = type("Args", (), {"id": self.id, "terms": "office table",
                                 "provider": "pexels", "execute": True})()
        with patch.object(materials.subprocess, "run",
                          return_value=subprocess.CompletedProcess([], 0, "", "")
        ) as runner, patch("builtins.input",
                           side_effect=AssertionError("unexpected footage approval prompt")):
            materials.cmd_fetch_online(args, self.root, self.knowledge)
            self.assertEqual(runner.call_count, 1)
            self.assertIn("--stop-at", runner.call_args.args[0])
            self.assertIn("materials", runner.call_args.args[0])

    def test_optional_mcp_registration_has_no_second_approval(self):
        with patch("builtins.input", side_effect=AssertionError("unexpected registration prompt")
        ), patch.object(sys, "argv", ["configure_mcp.py", "--root", str(self.root),
                                      "--enable-xhs"]):
            self.assertEqual(configure_mcp.main(), 0)
        saved = (self.root / ".codex" / "config.toml").read_text(encoding="utf-8")
        self.assertIn("[mcp_servers.xiaohongshu]", saved)
        self.assertNotIn("AUTH_TOKEN=", saved)

    def test_confirm_published_requires_scoped_official_link_without_prompt(self):
        # The original (draft-only) task can never be marked published.
        ledger = self.folder / "publish-ledger.json"
        data = json.loads(ledger.read_text("utf-8"))
        data["platforms"]["douyin"] = {"state": "submitted_unknown", "account": "main"}
        write(ledger, data)
        self.assertEqual(self.studio("confirm-published", "--id", self.id, "--platform", "douyin",
                                      "--url", "https://www.douyin.com/video/123").returncode, 2)

        created = self.studio("new", "--id", "authorized-verify", "--title", "允许发布的任务",
                              "--publish-target", "douyin:main")
        self.assertEqual(created.returncode, 0, created.stderr)
        authorized_ledger = self.root / "outputs" / "authorized-verify" / "publish-ledger.json"
        content = json.loads(authorized_ledger.read_text("utf-8"))
        content["platforms"]["douyin"] = {"state": "submitted_unknown", "account": "main"}
        write(authorized_ledger, content)
        for bad_url in ("http://www.douyin.com/video/123", "https://example.com/video/123"):
            self.assertEqual(self.studio("confirm-published", "--id", "authorized-verify",
                                          "--platform", "douyin", "--url", bad_url).returncode, 2)
        result = self.studio("confirm-published", "--id", "authorized-verify",
                             "--platform", "douyin", "--url", "https://www.douyin.com/video/123")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(authorized_ledger.read_text("utf-8"))["platforms"]["douyin"]["state"], "published")


if __name__ == "__main__":
    unittest.main()