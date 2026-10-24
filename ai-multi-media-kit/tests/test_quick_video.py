"""Isolated quick-route preflight checks and an opt-in real render."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave
from argparse import Namespace
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO

ROOT = Path(__file__).resolve().parents[1]
STUDIO = ROOT / "scripts" / "studio.py"
sys.path.insert(0, str(ROOT / "scripts"))
import quick_video
import studio


def dump(path: Path, data: dict):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


class QuickVideoTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        self.root = base / "tools"
        self.knowledge = base / "knowledge"
        self.output = base / "projects"
        (self.root / "config").mkdir(parents=True)
        self.knowledge.mkdir()
        self.output.mkdir()
        (self.knowledge / "review-rules.md").write_text("Use real reviewed claims.", encoding="utf8")
        dump(self.root / "config" / "workspace.json", {
            "install_root": str(self.root), "knowledge_root": str(self.knowledge),
            "output_root": str(self.output)
        })
        self.image = base / "screen.svg"
        self.image.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="960">'
            '<rect width="640" height="960" fill="#176c84"/>'
            '<text x="80" y="320" fill="white" font-size="55">SAMPLE</text></svg>', encoding="utf8")
        self.audio = base / "voice.wav"
        with wave.open(str(self.audio), "wb") as track:
            track.setnchannels(1)
            track.setsampwidth(2)
            track.setframerate(16000)
            track.writeframes(b"\0\0" * (16000 * 2))
        self.spec = base / "brief.json"
        dump(self.spec, {
            "title": "A cloud AI connection",
            "audience": "People working with local files",
            "primary_value": "Connect cloud AI to local tools",
            "shots": [{
                "title": "Local tools + cloud AI",
                "caption": "A bridge between two worlds",
                "seconds": 3.0,
                "image": str(self.image),
                "voiceover": "A computer can do more with local tools.",
                "audio": str(self.audio)
            }]
        })
        self.fake_skill = base / "skill"
        (self.fake_skill / "template").mkdir(parents=True)
        (self.fake_skill / "SKILL.md").write_text("---\nname: video-shotcraft\ndescription: test provider\n---\n", encoding="utf8")
        (self.fake_skill / "LICENSE").write_text("Apache-2.0 test fixture", encoding="utf8")
        for filename in ("package.json", "package-lock.json", "tsconfig.json", "remotion.config.ts"):
            shutil.copyfile(ROOT / "assets" / "quick-remotion" / filename, self.fake_skill / "template" / filename)

    def call(self, *extra, skill=None, timeout=180):
        command = [str(STUDIO), "--root", str(self.root), "quick", "--spec", str(self.spec),
                   "--topic", "local-tools", "--agent", "codex",
                   *(["--shotcraft-dir", str(skill)] if skill else []), *list(map(str, extra))]
        if "--dry-run" in extra:
            stdout, stderr = StringIO(), StringIO()
            with patch.object(sys, "argv", command), redirect_stdout(stdout), redirect_stderr(stderr), \
                    patch.object(quick_video, "ensure_tools", return_value=("npm", "npx")):
                code = studio.main()
            return subprocess.CompletedProcess(command, code, stdout.getvalue(), stderr.getvalue())
        return subprocess.run([sys.executable, "-X", "utf8", *command],
                              capture_output=True, text=True,
                              encoding="utf8", errors="replace", timeout=timeout)

    def test_dry_run_never_creates_project(self):
        reply = self.call("--dry-run")
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn("built-in", reply.stdout)
        self.assertIn("remotion", reply.stdout.lower())
        self.assertFalse(list(self.output.iterdir()))

    def test_missing_image_rejected_without_creating_project(self):
        brief = json.loads(self.spec.read_text("utf8"))
        brief["shots"][0]["image"] = "missing.png"
        dump(self.spec, brief)
        reply = self.call("--dry-run")
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("素材", reply.stderr)
        self.assertFalse(list(self.output.iterdir()))

    def test_missing_provider_license_is_rejected_before_output(self):
        (self.fake_skill / "LICENSE").unlink()
        reply = self.call("--dry-run", skill=self.fake_skill)
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("video-shotcraft", reply.stderr)
        self.assertFalse(list(self.output.iterdir()))

    def test_explicit_provider_does_not_require_effect_or_music_assets(self):
        reply = self.call("--dry-run", skill=self.fake_skill)
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn("video-shotcraft", reply.stdout)
        self.assertFalse(list(self.output.iterdir()))

    def test_broken_workspace_is_rejected_before_project_creation(self):
        (self.knowledge / "review-rules.md").unlink()
        reply = self.call("--dry-run")
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("review-rules.md", reply.stderr)
        self.assertFalse(list(self.output.iterdir()))

    def test_audio_longer_than_shot_is_rejected(self):
        brief = json.loads(self.spec.read_text("utf8"))
        brief["shots"][0]["seconds"] = 2.0
        dump(self.spec, brief)
        reply = self.call("--dry-run")
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("配音", reply.stderr)
        self.assertFalse(list(self.output.iterdir()))

    def test_no_narration_is_explicitly_flagged_in_plan(self):
        brief = json.loads(self.spec.read_text("utf8"))
        brief["shots"][0].pop("audio")
        dump(self.spec, brief)
        reply = self.call("--dry-run")
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn("voice_missing", reply.stdout)
        self.assertFalse(list(self.output.iterdir()))

    def test_intentionally_silent_shot_is_not_missing_narration(self):
        brief = json.loads(self.spec.read_text("utf8"))
        brief["shots"][0].pop("audio")
        brief["shots"][0].pop("voiceover")
        dump(self.spec, brief)
        reply = self.call("--dry-run")
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn('"voice_missing": []', reply.stdout)
        self.assertIn('"silent_shots": [1]', reply.stdout)
        self.assertFalse(list(self.output.iterdir()))

    def test_dry_run_validates_identity_and_collision(self):
        reply = self.call("--dry-run", "--agent", "bad/agent")
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("agent", reply.stderr)
        self.assertFalse(list(self.output.iterdir()))
        existing = self.output / "local-tools-codex-model-unknown-existing"
        existing.mkdir()
        reply = self.call("--dry-run", "--run-id", "existing")
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("禁止覆盖", reply.stderr)
        self.assertEqual(list(self.output.iterdir()), [existing])

    def test_dry_run_reports_missing_runtime_before_project_creation(self):
        args = Namespace(root=str(self.root), spec=str(self.spec), topic="local-tools", agent="codex",
                         model=None, run_id=None, shotcraft_dir=None, dry_run=True)
        with patch.object(quick_video.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "Node.js/npm"):
                quick_video.run_quick(args, studio)
        self.assertFalse(list(self.output.iterdir()))

    def test_compressed_audio_requires_duration_probe(self):
        brief = json.loads(self.spec.read_text("utf8"))
        audio = self.audio.with_suffix(".mp3")
        audio.write_bytes(b"not-an-audio-file")
        brief["shots"][0]["audio"] = str(audio)
        with self.assertRaisesRegex(ValueError, "ffprobe"):
            quick_video.checked_spec(brief, self.spec)
        self.assertFalse(list(self.output.iterdir()))

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "Requires local FFmpeg for compressed-audio fixture")
    def test_compressed_audio_cannot_be_silently_truncated(self):
        for extension in (".mp3", ".m4a"):
            with self.subTest(extension=extension):
                audio = self.audio.with_suffix(extension)
                conversion = subprocess.run([shutil.which("ffmpeg"), "-v", "error", "-i", str(self.audio), str(audio)],
                                            capture_output=True, timeout=30)
                self.assertEqual(conversion.returncode, 0, conversion.stderr)
                brief = json.loads(self.spec.read_text("utf8"))
                brief["shots"][0].update(audio=str(audio), seconds=2)
                dump(self.spec, brief)
                reply = self.call("--dry-run")
                self.assertNotEqual(reply.returncode, 0)
                self.assertIn("配音过长", reply.stderr)
                self.assertFalse(list(self.output.iterdir()))

    @unittest.skipUnless(os.environ.get("AI_MEDIA_QUICK_REAL_RENDER") == "1", "Run explicitly for real Remotion smoke")
    def test_real_mp4_keeps_full_review_and_publish_guardrails(self):
        response = self.call(timeout=800)
        self.assertEqual(response.returncode, 0, response.stderr)
        self.assertIn("QUICK_VIDEO_READY", response.stdout)
        outputs = list(self.output.iterdir())
        self.assertEqual(len(outputs), 1)
        project = outputs[0]
        self.assertTrue((project / "成品视频.mp4").stat().st_size > 4000)
        self.assertTrue((project / "视频封面.png").stat().st_size > 1000)
        engine=project/"99-专业工程"
        self.assertTrue((engine / "src" / "Quick.tsx").is_file())
        npx = shutil.which("npx")
        self.assertIsNotNone(npx)
        typing = subprocess.run([npx, "--no-install", "tsc", "--noEmit"],
                                cwd=engine, capture_output=True, text=True,
                                encoding="utf8", errors="replace", timeout=35)
        self.assertEqual(typing.returncode, 0, typing.stderr)
        frame = engine / "check-frame.png"
        still = subprocess.run([npx, "--no-install", "remotion", "still", "src/index.tsx",
                                "QuickVideo", str(frame), "--frame=35", "--log=error"],
                               cwd=engine, capture_output=True, text=True,
                               encoding="utf8", errors="replace", timeout=80)
        self.assertEqual(still.returncode, 0, still.stderr)
        with frame.open("rb") as image:
            self.assertEqual(image.read(8), b"\x89PNG\r\n\x1a\n")
            image.read(8)
            self.assertEqual(struct.unpack(">II", image.read(8)), (1080, 1920))
        self.assertFalse((engine / "src" / "FlashCut.tsx").exists())
        self.assertFalse((engine / "public").exists())
        scripts = json.loads((engine / "package.json").read_text("utf8"))["scripts"]
        self.assertIn("QuickVideo", scripts["render"])
        self.assertIn("src/index.tsx", scripts["dev"])
        self.assertEqual(len(list((project / "02-媒体素材" / "图片").glob("*.svg"))),1)
        self.assertEqual(len(list((project / "02-媒体素材" / "配音").glob("*.wav"))),1)
        self.assertTrue((project / "01-文案与分镜" / "分镜脚本.md").is_file())
        self.assertFalse((project / "review.json").exists())
        self.assertFalse((engine / "video" / "review.json").exists())
        self.assertTrue((engine / "publish-ledger.json").exists())
        check = subprocess.run([sys.executable, "-X", "utf8", str(STUDIO), "--root",
                                str(self.root), "package", "--id", project.name],
                               capture_output=True, text=True, encoding="utf8", errors="replace",
                               timeout=30)
        self.assertNotEqual(check.returncode, 0)
        meta = json.loads((engine / "video" / "render.json").read_text("utf8"))
        self.assertEqual(meta["engine"], "remotion")
        self.assertTrue(meta["video_sha256"])
        self.assertEqual(meta["video_sha256"], __import__("hashlib").sha256(
            (project / "成品视频.mp4").read_bytes()).hexdigest())
        self.assertEqual(meta["render_status"], "technical_only")
        self.assertFalse((engine / "platforms").exists())
        original=(project/"成品视频.mp4").read_bytes()
        board=project/"01-文案与分镜"/"分镜脚本.md"
        board.write_text(board.read_text("utf8").replace("- 时长：3 秒","- 时长：4 秒")
                         .replace("Local tools + cloud AI","Edit here via Chinese storyboard"),encoding="utf8")
        plan=subprocess.run([sys.executable,"-X","utf8",str(STUDIO),"--root",str(self.root),
                             "rebuild","--id",project.name,"--dry-run"],
                             capture_output=True,text=True,encoding="utf8",timeout=30)
        self.assertEqual(plan.returncode,0,plan.stderr)
        self.assertEqual((project/"成品视频.mp4").read_bytes(),original)
        rerender=subprocess.run([sys.executable,"-X","utf8",str(STUDIO),"--root",str(self.root),
                                 "rebuild","--id",project.name],capture_output=True,
                                 text=True,encoding="utf8",timeout=600)
        self.assertEqual(rerender.returncode,0,rerender.stderr)
        self.assertIn("VIDEO_REBUILT",rerender.stdout)
        self.assertNotEqual((project/"成品视频.mp4").read_bytes(),original)
        self.assertEqual(len(list((project/"03-修改与版本").glob("旧成片-*.mp4"))),1)
        self.assertEqual(len(list((project/"03-修改与版本").glob("旧封面-*.png"))),1)
        self.assertTrue((project/"视频封面.png").stat().st_size>1000)
        self.assertEqual(json.loads((engine/"shotlist.json").read_text("utf8"))["shots"][0]["frames"],120)
        refreshed=json.loads((engine/"video"/"render.json").read_text("utf8"))
        self.assertEqual(refreshed["video_sha256"],__import__("hashlib").sha256(
            (project/"成品视频.mp4").read_bytes()).hexdigest())
        self.assertFalse((engine/"video"/"review.json").exists())


if __name__ == "__main__":
    unittest.main()
