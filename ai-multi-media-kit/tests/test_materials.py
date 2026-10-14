"""Material-source workflow tests: offline only; use synthetic video bytes."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(script, *args, stdin=None):
    return subprocess.run(
        [sys.executable, "-X", "utf8", str(ROOT / "scripts" / script), *map(str, args)],
        capture_output=True, text=True, encoding="utf-8", errors="replace", input=stdin, timeout=30
    )


class MaterialSourcesTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.root = self.base / "Tools with spaces"
        self.knowledge = self.base / "Company Data"
        result = run("init_workspace.py", "--install-root", self.root,
                     "--knowledge-root", self.knowledge)
        self.assertEqual(result.returncode, 0, result.stderr)

    def materials(self, *args):
        return run("materials.py", "--root", self.root, *args)

    def test_first_run_registers_local_library_and_preserves_on_repeat(self):
        registry = self.root / "config" / "material-sources.json"
        self.assertTrue(registry.is_file())
        data = json.loads(registry.read_text(encoding="utf-8"))
        self.assertEqual(data["sources"][0]["name"], "company-library")
        self.assertEqual(data["sources"][0]["path"], str(self.knowledge / "materials"))
        self.assertEqual(data["sources"][0]["rights"], "unverified")
        data["sources"][0]["rights"] = "owned"
        registry.write_text(json.dumps(data), encoding="utf-8")
        again = run("init_workspace.py", "--install-root", self.root,
                    "--knowledge-root", self.knowledge)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(json.loads(registry.read_text("utf-8"))["sources"][0]["rights"], "owned")

    def test_add_scan_annotate_search_and_skip_symlinks(self):
        library = self.base / "NAS media"
        library.mkdir()
        (library / "宠物喂食.mp4").write_bytes(b"fake mp4 for indexing only")
        (library / "other.txt").write_text("skip", encoding="utf-8")
        # A symlink outside the source must not be indexed.
        try:
            (library / "outside.mp4").symlink_to(self.knowledge / "brand.md")
        except (OSError, NotImplementedError):
            pass

        add = self.materials("add-source", "--name", "nas", "--path", library)
        self.assertEqual(add.returncode, 0, add.stderr)
        scan = self.materials("scan")
        self.assertEqual(scan.returncode, 0, scan.stderr)
        items = json.loads(self.materials("search", "--query", "宠物").stdout)["items"]
        self.assertEqual(len(items), 1, items)
        asset_id = items[0]["id"]
        self.assertEqual(items[0]["rights"], "unverified")
        annotated = self.materials("annotate", "--id", asset_id,
                                   "--tags", "喂食,宠物,实拍",
                                   "--description", "宠物吃粮镜头",
                                   "--rights", "owned", "--license-note", "公司自行拍摄")
        self.assertEqual(annotated.returncode, 0, annotated.stderr)
        after = self.materials("scan")
        self.assertEqual(after.returncode, 0, after.stderr)
        found = json.loads(self.materials("search", "--query", "实拍").stdout)["items"]
        self.assertEqual(found[0]["id"], asset_id)
        self.assertEqual(found[0]["rights"], "owned")
        self.assertEqual(found[0]["license_note"], "公司自行拍摄")

    def test_temporary_file_provenance_and_changed_file_rejected(self):
        temp_clip = self.base / "temporary_video.mp4"
        temp_clip.write_bytes(b"first")
        add = self.materials("add-file", "--path", temp_clip, "--tags", "户外,城市",
                             "--rights", "licensed", "--license-note", "仅演示用授权",
                             "--source-url", "https://example.org/video/123")
        self.assertEqual(add.returncode, 0, add.stderr)
        item = json.loads(self.materials("search", "--query", "户外").stdout)["items"][0]
        self.assertEqual(item["source_url"], "https://example.org/video/123")
        self.assertEqual(item["source"], "one-off")
        temp_clip.write_bytes(b"changed content since indexing")
        bad = self.materials("resolve", "--ids", item["id"])
        self.assertEqual(bad.returncode, 2)
        self.assertIn("已变化", bad.stderr)

    def test_unverified_media_cannot_be_selected_and_no_url_download(self):
        clip = self.knowledge / "materials" / "sample.mp4"
        clip.write_bytes(b"sample")
        self.assertEqual(self.materials("scan").returncode, 0)
        item = json.loads(self.materials("search", "--query", "sample").stdout)["items"][0]
        p = self.materials("resolve", "--ids", item["id"])
        self.assertEqual(p.returncode, 2)
        self.assertIn("授权", p.stderr)
        self.assertFalse((self.root / "runtime" / "material-previews").exists())

    def test_source_registration_rejects_missing_folder_and_duplicate(self):
        missing = self.base / "not-mounted"
        p = self.materials("add-source", "--name", "network-share", "--path", missing)
        self.assertEqual(p.returncode, 2)
        self.assertFalse(missing.exists())
        existing = self.materials("add-source", "--name", "company-library",
                                  "--path", self.knowledge / "materials")
        self.assertEqual(existing.returncode, 2)

    def test_studio_accepts_ids_with_approval_but_does_not_render_in_dry_run(self):
        clip = self.knowledge / "materials" / "foo.mp4"
        clip.write_bytes(b"test bytes")
        self.assertEqual(self.materials("scan").returncode, 0)
        item = json.loads(self.materials("search", "--query", "foo").stdout)["items"][0]
        self.assertEqual(self.materials("annotate", "--id", item["id"],
                                       "--rights", "owned", "--license-note", "原创").returncode, 0)
        cid = "test-assets-1"
        self.assertEqual(run("studio.py", "--root", self.root, "new", "--id", cid,
                             "--title", "素材测试视频").returncode, 0)
        folder = self.root / "outputs" / cid
        p = {
            "content_id": cid, "title": "原创视频脚本", "duration_seconds": 5,
            "narration": "这是一条原创素材测试视频的脚本。",
            "shots": [{"seconds": 5, "visual": "素材视频", "voiceover": "原创视频"}],
            "platforms": {v: {"title": "标题示例", "description": "", "tags": []}
                          for v in ("xiaohongshu","douyin","tencent","bilibili",
                                    "kuaishou","wechat_oa","zhihu")}
        }
        (folder/"script.json").write_text(json.dumps(p,ensure_ascii=False),encoding="utf-8")
        hashes = json.loads(run("studio.py", "--root", self.root, "hash", "--id", cid).stdout)
        review = {"result": "PASS", "checks": [{"rule": "事实核实","result":"PASS"}],
                  "facts_to_verify": [], **hashes}
        (folder/"review.json").write_text(json.dumps(review,ensure_ascii=False),encoding="utf-8")
        approve = run("studio.py","--root",self.root,"approve","--id",cid,"--stage","script",
                      "--who","Tester",stdin=f"APPROVE:{cid}:script\n")
        self.assertEqual(approve.returncode,0,approve.stderr)
        dry = run("studio.py", "--root", self.root, "render", "--id", cid,
                  "--engine", "ffmpeg", "--material-ids", item["id"],
                  "--rights-confirmed", "--dry-run")
        self.assertEqual(dry.returncode, 0, dry.stderr)
        self.assertIn("foo.mp4", dry.stdout)
        self.assertFalse((folder/"video"/"master.mp4").exists())
        missing = run("studio.py", "--root", self.root, "render", "--id", cid,
                      "--engine", "ffmpeg", "--materials", self.base / "missing.mp4",
                      "--rights-confirmed", "--dry-run")
        self.assertEqual(missing.returncode, 2)
        online = self.materials("fetch-online", "--id", cid, "--provider", "pexels",
                                "--terms", "office collaboration, computer")
        self.assertEqual(online.returncode, 0, online.stderr)
        self.assertIn("--stop-at", online.stdout)
        self.assertIn("materials", online.stdout)
        self.assertIn("--video-terms", online.stdout)
        self.assertFalse((folder/"video"/"master.mp4").exists())
        bad = run("studio.py", "--root", self.root, "render", "--id", cid, "--engine", "ffmpeg",
                  "--material-ids", "not-indexed", "--rights-confirmed", "--dry-run")
        self.assertEqual(bad.returncode, 2)
        self.assertFalse((folder/"video"/"master.mp4").exists())

    def test_doctor_checks_material_source_registration(self):
        report = self.base / "doctor.json"
        p = run("doctor.py", "--install-root", self.root, "--scope", "core",
                "--json-output", report)
        self.assertEqual(p.returncode, 0, p.stderr)
        entries = {x["name"]: x["ok"] for x in json.loads(report.read_text("utf8"))["checks"]}
        self.assertTrue(entries["素材来源登记"])
        self.assertTrue(entries["素材管理 CLI"])

    def test_owner_export_includes_material_index_but_not_external_video_bytes(self):
        from zipfile import ZipFile
        external = self.base / "NAS media"
        external.mkdir()
        file = external / "licensed.mp4"
        file.write_bytes(b"external raw bytes must stay at source")
        p = self.materials("add-file", "--path", file, "--rights", "licensed",
                           "--license-note", "business permission reference")
        self.assertEqual(p.returncode, 0, p.stderr)
        archive = self.base / "owner-assets.zip"
        exported = run("export_assets.py", "--install-root", self.root,
                       "--destination", archive)
        self.assertEqual(exported.returncode, 0, exported.stderr)
        with ZipFile(archive) as out:
            self.assertIn("materials/sources.json", out.namelist())
            self.assertIn("materials/index.json", out.namelist())
            self.assertIn("licensed.mp4", out.read("materials/index.json").decode("utf8"))
            self.assertFalse(any(s.endswith("licensed.mp4") for s in out.namelist()))


if __name__ == "__main__":
    unittest.main()
