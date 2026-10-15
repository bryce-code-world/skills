"""Offline integration tests for actual media paths and content guards."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def pyth(script, *args, timeout=80):
    return subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "scripts" / script),
                           *map(str, args)], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def jsonwrite(path, content):
    path.write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class StudioProductionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        local=patch.dict(os.environ,{'LOCALAPPDATA':str(base/'user-config'), 'XDG_CONFIG_HOME':str(base/'xdg-config')})
        local.start(); self.addCleanup(local.stop)
        self.root, self.knowledge = base / "install", base / "knowledge"
        result = pyth("init_workspace.py", "--install-root", self.root,
                      "--knowledge-root", self.knowledge)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.id = "video-test"
        result = self.call("new", "--id", self.id, "--title", "自动内容生产测试")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.d = self.root / "outputs" / self.id
        self.write_review()

    def call(self, *args, timeout=80):
        return pyth("studio.py", "--root", self.root, *args, timeout=timeout)

    def write_review(self):
        platforms = ("xiaohongshu", "douyin", "tencent", "bilibili", "kuaishou", "wechat_oa", "zhihu")
        jsonwrite(self.d / "script.json", {
            "content_id": self.id, "title": "小团队内容增长", "duration_seconds": 3,
            "narration": "确定用户问题，形成脚本与素材，再由 AI 自动验收交付。",
            "shots": [{"seconds": 3, "visual": "原创的工作场景", "voiceover": "自动制作"}],
            "platforms": {p: {"title": p + " 的原创标题", "description": "测试",
                              "tags": ["内容", "自动化"]} for p in platforms},
            "article_markdown": "# 小团队内容增长\n原创测试。",
        })
        hashes = json.loads(self.call("hash", "--id", self.id).stdout)
        jsonwrite(self.d / "review.json", {
            "result": "PASS", "score": 95, "checks": [
                {"rule": "事实准确", "result": "PASS", "reason": "原创测试素材"}],
            "facts_to_verify": [], "issues": [], **hashes,
        })

    def test_new_never_overwrites(self):
        brief = self.d / "brief.md"
        brief.write_text("重要人工补充", encoding="utf-8")
        p = self.call("new", "--id", self.id, "--title", "错误重建")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(brief.read_text("utf-8"), "重要人工补充")

    def test_ai_review_is_revision_sensitive_without_human_checkpoint(self):
        checked = json.loads(self.call("check", "--id", self.id).stdout)
        self.assertEqual(checked["script_ready"], "valid")
        r = json.loads((self.d / "review.json").read_text("utf-8"))
        r["facts_to_verify"] = ["尚未核对"]
        jsonwrite(self.d / "review.json", r)
        checked = json.loads(self.call("check", "--id", self.id).stdout)
        self.assertIn("待核", checked["script_ready"])
        r["facts_to_verify"] = []
        jsonwrite(self.d / "review.json", r)
        self.knowledge.joinpath("review-rules.md").write_text("更严格的新审核标准", encoding="utf-8")
        checked = json.loads(self.call("check", "--id", self.id).stdout)
        self.assertIn("审核标准", checked["script_ready"])

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg unavailable")
    def test_real_video_packaging_needs_ai_review_but_not_human_approval(self):
        clip = self.root / "original.mp4"
        make = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
             "-i", "color=c=navy:s=160x280:r=15:d=2",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", str(clip)],
            capture_output=True, timeout=60,
        )
        self.assertEqual(make.returncode, 0, make.stderr.decode(errors="replace"))
        added = pyth("materials.py", "--root", self.root, "add-file", "--path", clip,
                     "--rights", "owned", "--license-note", "原生测试色块")
        self.assertEqual(added.returncode, 0, added.stderr)
        asset_id = json.loads(added.stdout)["id"]
        render = self.call("render", "--id", self.id, "--engine", "ffmpeg",
                           "--material-ids", asset_id, "--rights-confirmed",
                           "--width", "180", "--height", "320", timeout=180)
        self.assertEqual(render.returncode, 0, render.stderr)
        video = self.d / "video" / "master.mp4"
        self.assertTrue(video.is_file())
        check = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,width,height",
             "-of", "json", str(video)], capture_output=True, text=True, timeout=25,
        )
        self.assertEqual(check.returncode, 0, check.stderr)
        streams = json.loads(check.stdout)["streams"]
        self.assertEqual({item["codec_type"] for item in streams}, {"video", "audio"})
        self.assertEqual(self.call("package", "--id", self.id).returncode, 2)
        self.assertFalse((self.d / "approvals").exists())
        meta = json.loads((self.d / "video" / "render.json").read_text("utf-8"))
        hashes = json.loads(self.call("hash", "--id", self.id).stdout)
        jsonwrite(self.d / "video" / "review.json", {
            "result": "PASS", "checks": [
                {"rule": "画面、时长与字幕检查", "result": "PASS", "reason": "测试文件已通过 ffprobe"}],
            "issues": [], "facts_to_verify": [],
            "video_sha256": meta["video_sha256"],
            "script_sha256": hashes["script_sha256"],
            "review_standard_sha256": hashes["review_standard_sha256"],
        })
        self.assertEqual(self.call("package", "--id", self.id).returncode, 0)
        self.assertEqual(len(list((self.d / "platforms").glob("*/package.json"))), 7)

    def test_fake_import_rejected(self):
        fake = self.root / "fake.mp4"
        fake.write_bytes(b"not an mp4")
        res = self.call("import-video", "--id", self.id, "--file", fake)
        self.assertEqual(res.returncode, 2)
        self.assertFalse((self.d / "video" / "master.mp4").exists())

    def test_installer_plan_has_no_side_effect(self):
        plan = pyth("installer.py", "--root", self.root, "--profile", "core")
        self.assertEqual(plan.returncode, 0, plan.stderr)
        self.assertIn("PLAN_ONLY", plan.stdout)
        self.assertFalse((self.root / "tools" / "marketingskills").exists())


if __name__ == "__main__":
    unittest.main()
