"""End-to-end, isolated tests for the opt-in video-shotcraft quick route."""
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
import wave

ROOT = Path(__file__).resolve().parents[1]
STUDIO = ROOT / "scripts" / "studio.py"
UPSTREAM = Path.home() / ".codex" / "skills" / "video-shotcraft"


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
        (self.fake_skill / "assets" / "lib").mkdir(parents=True)
        (self.fake_skill / "assets" / "audio" / "bgm").mkdir(parents=True)
        (self.fake_skill / "assets" / "audio").mkdir(exist_ok=True)
        (self.fake_skill / "SKILL.md").write_text("---\nname: video-shotcraft\ndescription: test provider\n---\n", encoding="utf8")
        (self.fake_skill / "LICENSE").write_text("Apache-2.0 test fixture", encoding="utf8")
        (self.fake_skill / "template" / "package.json").write_text("{}\n", encoding="utf8")
        (self.fake_skill / "template" / "package-lock.json").write_text("{}\n", encoding="utf8")
        (self.fake_skill / "template" / "tsconfig.json").write_text("{}\n", encoding="utf8")
        (self.fake_skill / "template" / "remotion.config.ts").write_text("export {};\n", encoding="utf8")
        (self.fake_skill / "assets" / "lib" / "FlashCut.tsx").write_text("export const FlashCut=()=>null;\n", encoding="utf8")
        (self.fake_skill / "assets" / "audio" / "bgm" / "house-vibez.mp3").write_bytes(b"fake-bgm")
        (self.fake_skill / "assets" / "audio" / "ATTRIBUTION.md").write_text("Synthetic test provider.", encoding="utf8")

    def call(self, *extra, skill=None, timeout=180):
        return subprocess.run([sys.executable, "-X", "utf8", str(STUDIO),
                               "--root", str(self.root), "quick", "--spec", str(self.spec),
                               "--topic", "local-tools", "--agent", "codex",
                               "--shotcraft-dir", str(skill or self.fake_skill),
                               *list(map(str, extra))],
                              capture_output=True, text=True,
                              encoding="utf8", errors="replace", timeout=timeout)

    def test_dry_run_never_creates_project(self):
        reply = self.call("--dry-run")
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn("video-shotcraft", reply.stdout)
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
        reply = self.call("--dry-run")
        self.assertNotEqual(reply.returncode, 0)
        self.assertIn("video-shotcraft", reply.stderr)
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

    def test_missing_narration_and_audio_is_still_flagged(self):
        brief = json.loads(self.spec.read_text("utf8"))
        brief["shots"][0].pop("audio")
        brief["shots"][0].pop("voiceover")
        dump(self.spec, brief)
        reply = self.call("--dry-run")
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertIn('"voice_missing": [1]', reply.stdout)
        self.assertFalse(list(self.output.iterdir()))

    @unittest.skipUnless(os.environ.get("AI_MEDIA_QUICK_REAL_RENDER") == "1", "Run explicitly for real Remotion smoke")
    def test_real_mp4_keeps_full_review_and_publish_guardrails(self):
        if not (UPSTREAM / "template" / "package-lock.json").is_file():
            self.skipTest("video-shotcraft is not installed")
        response = self.call(skill=UPSTREAM, timeout=260)
        self.assertEqual(response.returncode, 0, response.stderr)
        self.assertIn("QUICK_VIDEO_READY", response.stdout)
        outputs = list(self.output.iterdir())
        self.assertEqual(len(outputs), 1)
        project = outputs[0]
        self.assertTrue((project / "video" / "master.mp4").stat().st_size > 4000)
        self.assertTrue((project / "src" / "Quick.tsx").is_file())
        npx = shutil.which("npx")
        self.assertIsNotNone(npx)
        typing = subprocess.run([npx, "--no-install", "tsc", "--noEmit"],
                                cwd=project, capture_output=True, text=True,
                                encoding="utf8", errors="replace", timeout=35)
        self.assertEqual(typing.returncode, 0, typing.stderr)
        frame = project / "check-frame.png"
        still = subprocess.run([npx, "--no-install", "remotion", "still", "src/index.tsx",
                                "QuickVideo", str(frame), "--frame=35", "--log=error"],
                               cwd=project, capture_output=True, text=True,
                               encoding="utf8", errors="replace", timeout=80)
        self.assertEqual(still.returncode, 0, still.stderr)
        with frame.open("rb") as image:
            self.assertEqual(image.read(8), b"\x89PNG\r\n\x1a\n")
            image.read(8)
            self.assertEqual(struct.unpack(">II", image.read(8)), (1080, 1920))
        self.assertTrue((project / "src" / "FlashCut.tsx").is_file())
        self.assertTrue((project / "docs" / "video-shotcraft-LICENSE.txt").is_file())
        scripts = json.loads((project / "package.json").read_text("utf8"))["scripts"]
        self.assertIn("QuickVideo", scripts["render"])
        self.assertIn("src/index.tsx", scripts["dev"])
        self.assertTrue((project / "public" / "screens" / "shot-01.svg").exists())
        self.assertTrue((project / "public" / "audio" / "shot-01.wav").exists())
        self.assertFalse((project / "review.json").exists())
        self.assertFalse((project / "video" / "review.json").exists())
        self.assertTrue((project / "publish-ledger.json").exists())
        check = subprocess.run([sys.executable, "-X", "utf8", str(STUDIO), "--root",
                                str(self.root), "package", "--id", project.name],
                               capture_output=True, text=True, encoding="utf8", errors="replace",
                               timeout=30)
        self.assertNotEqual(check.returncode, 0)
        meta = json.loads((project / "video" / "render.json").read_text("utf8"))
        self.assertEqual(meta["engine"], "remotion")
        self.assertTrue(meta["video_sha256"])
        self.assertEqual(meta["video_sha256"], __import__("hashlib").sha256(
            (project / "video" / "master.mp4").read_bytes()).hexdigest())
        self.assertEqual(meta["render_status"], "technical_only")
        self.assertFalse((project / "platforms").exists())


if __name__ == "__main__":
    unittest.main()
