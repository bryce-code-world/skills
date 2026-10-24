"""User-readable deliverable layout and synchronization contract."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
STUDIO=ROOT/"scripts"/"studio.py"


class UserProjectTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base=Path(tmp.name)
        self.tool=base/"tool"
        self.kb=base/"knowledge"
        self.out=base/"projects"
        (self.tool/"config").mkdir(parents=True)
        self.kb.mkdir()
        self.out.mkdir()
        (self.kb/"review-rules.md").write_text("Only reviewed assets.",encoding="utf8")
        (self.tool/"config"/"workspace.json").write_text(json.dumps({
            "install_root":str(self.tool),"knowledge_root":str(self.kb),"output_root":str(self.out)
        }),encoding="utf8")

    def call(self,*args):
        return subprocess.run([sys.executable,"-X","utf8",str(STUDIO),"--root",str(self.tool),*map(str,args)],
                              capture_output=True,text=True,encoding="utf8",timeout=25)

    def new(self):
        r=self.call("new","--topic","clip","--agent","codex","--run-id","phase1","--title","视频制作体验")
        self.assertEqual(r.returncode,0,r.stderr)
        return self.out/"clip-codex-model-unknown-phase1"

    def test_new_project_has_chinese_user_surface_and_private_engine(self):
        p=self.new()
        self.assertTrue((p/"打开这里.md").is_file())
        self.assertTrue((p/"01-文案与分镜"/"视频文案.md").is_file())
        self.assertTrue((p/"01-文案与分镜"/"分镜脚本.md").is_file())
        self.assertTrue((p/"02-媒体素材"/"图片").is_dir())
        self.assertTrue((p/"02-媒体素材"/"视频片段").is_dir())
        self.assertTrue((p/"02-媒体素材"/"配音").is_dir())
        self.assertTrue((p/"02-媒体素材"/"背景音乐").is_dir())
        self.assertTrue((p/"02-媒体素材"/"音效").is_dir())
        self.assertTrue((p/"03-修改与版本"/"修改记录.md").is_file())
        self.assertTrue((p/"99-专业工程"/"content.json").is_file())
        self.assertTrue((p/"99-专业工程"/"script.template.json").is_file())
        for fn in ("content.json","script.template.json","publish-ledger.json","package.json","shotlist.json"):
            self.assertFalse((p/fn).exists(),f"{fn} leaks into normal user-facing root")
        listing=self.call("list","--topic","clip")
        self.assertEqual(listing.returncode,0,listing.stderr)
        items=json.loads(listing.stdout)["items"]
        self.assertEqual(len(items),1)
        self.assertEqual(items[0]["directory"],str(p))

    def test_chinese_storyboard_can_drive_engine_and_invalidate_prior_review(self):
        p=self.new()
        eng=p/"99-专业工程"
        script={
            "content_id":p.name,"title":"视频制作体验","narration":"这是一段正常长度的口播文案。",
            "duration_seconds":3,
            "editorial_intent":{"audience":"普通用户","primary_value":"用更简单的方式制作视频","secondary_values":[],"evidence_plan":["实际测试素材"]},
            "shots":[{"seconds":3,"visual":"初始画面","voiceover":"这是一段正常长度的口播文案。"}],
            "platforms":{}
        }
        (eng/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        created=self.call("storyboard","--id",p.name,"--from-engine")
        self.assertEqual(created.returncode,0,created.stderr)
        source=p/"01-文案与分镜"/"分镜脚本.md"
        raw=source.read_text(encoding="utf8")
        self.assertIn("初始画面",raw)
        self.assertIn("这是一段正常长度的口播文案。",(p/"01-文案与分镜"/"视频文案.md").read_text("utf8"))
        source.write_text(raw.replace("初始画面","用户修改后的画面").replace("3 秒","4 秒"),encoding="utf8")
        synced=self.call("storyboard","--id",p.name,"--apply")
        self.assertEqual(synced.returncode,0,synced.stderr)
        updated=json.loads((eng/"script.json").read_text(encoding="utf8"))
        self.assertEqual(updated["shots"][0]["visual"],"用户修改后的画面")
        self.assertEqual(updated["duration_seconds"],4)
        self.assertIn("用户修改后的画面",(p/"01-文案与分镜"/"分镜脚本.md").read_text("utf8"))
        self.assertTrue(any((eng/"history").glob("*/script.json")))

    def test_unapplied_user_changes_block_old_script_validation(self):
        p=self.new()
        engine=p/"99-专业工程"
        script={
            "content_id":p.name,"title":"视频制作体验","narration":"真实的用户口播。",
            "duration_seconds":3,
            "editorial_intent":{"audience":"创作者","primary_value":"减少重复操作","secondary_values":[],"evidence_plan":["演示成片"]},
            "shots":[{"seconds":3,"visual":"第一个画面","voiceover":"真实的用户口播。"}],"platforms":{}
        }
        (engine/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        self.assertEqual(self.call("storyboard","--id",p.name,"--from-engine").returncode,0)
        board=p/"01-文案与分镜"/"分镜脚本.md"
        board.write_text(board.read_text("utf8").replace("第一个画面","用户改了画面"),encoding="utf8")
        result=self.call("check","--id",p.name)
        self.assertNotEqual(result.returncode,0)
        self.assertIn("中文分镜",result.stderr)
        self.assertEqual(self.call("storyboard","--id",p.name,"--apply").returncode,0)
        self.assertEqual(self.call("check","--id",p.name).returncode,0)

    def test_early_user_storyboard_draft_is_not_overwritten_by_first_export(self):
        p=self.new()
        doc=p/"01-文案与分镜"/"分镜脚本.md"
        doc.write_text(doc.read_text("utf8")+"\\n用户先写了自己的故事大纲。",encoding="utf8")
        engine=p/"99-专业工程"
        script={"content_id":p.name,"title":"视频制作体验","narration":"真实的用户口播。",
                "duration_seconds":3,"shots":[{"seconds":3,"visual":"工具自动画面","voiceover":"真实的用户口播。"}],
                "platforms":{}}
        (engine/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        result=self.call("storyboard","--id",p.name,"--from-engine")
        self.assertNotEqual(result.returncode,0)
        self.assertIn("中文分镜",result.stderr)
        self.assertIn("用户先写了",doc.read_text("utf8"))

    def test_changing_master_voice_is_reflected_in_engine_timeline(self):
        project=self.new()
        d=project/"99-专业工程"
        audio=project/"02-媒体素材"/"配音"
        (audio/"old.wav").write_bytes(b"old voice fixture")
        (audio/"new.wav").write_bytes(b"new voice fixture")
        script={"content_id":project.name,"title":"测试影片","duration_seconds":6,
                "narration":"一句开始。一句收尾。","shots":[
                   {"seconds":3,"visual":"镜头甲","voiceover":"一句开始。"},
                   {"seconds":3,"visual":"镜头乙","voiceover":"一句收尾。"}],"platforms":{}}
        (d/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        shots={"width":1080,"height":1920,"fps":30,"narration_audio":"配音/old.wav",
               "shots":[{"seconds":3,"frames":90,"title":"甲","caption":"","audio":None,"image":None},
                        {"seconds":3,"frames":90,"title":"乙","caption":"","audio":None,"image":None}]}
        (d/"shotlist.json").write_text(json.dumps(shots,ensure_ascii=False),encoding="utf8")
        out=self.call("storyboard","--id",project.name,"--from-engine")
        self.assertEqual(out.returncode,0,out.stderr)
        doc=project/"01-文案与分镜"/"分镜脚本.md"
        self.assertIn("配音/old.wav",doc.read_text("utf8"))
        doc.write_text(doc.read_text("utf8").replace("配音/old.wav","配音/new.wav"),encoding="utf8")
        result=self.call("storyboard","--id",project.name,"--apply")
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads((d/"shotlist.json").read_text("utf8"))["narration_audio"],"配音/new.wav")

    def test_edit_to_plain_narration_cannot_be_silently_overwritten(self):
        p=self.new()
        eng=p/"99-专业工程"
        script={"content_id":p.name,"title":"视频制作体验","narration":"这是完整的用户口播文本。",
                "duration_seconds":3,
                "shots":[{"seconds":3,"visual":"介绍画面","voiceover":"这是完整的用户口播文本。"}],
                "platforms":{}}
        (eng/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        self.assertEqual(self.call("storyboard","--id",p.name,"--from-engine").returncode,0)
        overview=p/"01-文案与分镜"/"视频文案.md"
        before=overview.read_text("utf8")
        self.assertIn("这是完整的用户口播文本。",before)
        overview.write_text(before+"\n额外补充的一行用户修改。",encoding="utf8")
        response=self.call("storyboard","--id",p.name,"--from-engine")
        self.assertNotEqual(response.returncode,0)
        self.assertIn("视频文案.md",response.stderr)
        attempt=self.call("storyboard","--id",p.name,"--apply")
        self.assertNotEqual(attempt.returncode,0)
        self.assertIn("视频文案.md",attempt.stderr)
        self.assertIn("额外补充",overview.read_text("utf8"))

    def test_malicious_asset_reference_is_rejected(self):
        p=self.new()
        engine=p/"99-专业工程"
        script={"content_id":p.name,"title":"视频制作体验","narration":"真实的用户口播。",
                "duration_seconds":3,"shots":[{"seconds":3,"visual":"画面","voiceover":"真实的用户口播。"}],
                "platforms":{}}
        (engine/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        self.assertEqual(self.call("storyboard","--id",p.name,"--from-engine").returncode,0)
        board=p/"01-文案与分镜"/"分镜脚本.md"
        board.write_text(board.read_text("utf8").replace("- 图片：无",
                         "- 图片：../../../../private.png"),encoding="utf8")
        result=self.call("storyboard","--id",p.name,"--apply")
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any((engine/"history").glob("*/script.json")))

    def test_concurrent_script_and_storyboard_edits_do_not_overwrite_each_other(self):
        project=self.new()
        engine=project/"99-专业工程"
        script={"content_id":project.name,"title":"视频制作体验","narration":"真实的用户口播。",
                "duration_seconds":3,"shots":[{"seconds":3,"visual":"旧画面","voiceover":"真实的用户口播。"}],
                "platforms":{}}
        original=engine/"script.json"
        original.write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        self.assertEqual(self.call("storyboard","--id",project.name,"--from-engine").returncode,0)
        doc=project/"01-文案与分镜"/"分镜脚本.md"
        doc.write_text(doc.read_text("utf8").replace("旧画面","用户改画面"),encoding="utf8")
        script["shots"][0]["visual"]="另一个 Agent 的修改"
        original.write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        result=self.call("storyboard","--id",project.name,"--apply")
        self.assertNotEqual(result.returncode,0)
        self.assertIn("独立修改",result.stderr)
        self.assertEqual(json.loads(original.read_text("utf8"))["shots"][0]["visual"],"另一个 Agent 的修改")
        self.assertIn("用户改画面",doc.read_text("utf8"))
        self.assertFalse((engine/"history").exists())

    def test_reusing_identical_image_does_not_copy_twice(self):
        from sys import path as system_paths
        system_paths.insert(0,str(ROOT/"scripts"))
        from project_layout import store_asset,relative_media
        project=self.new()
        engine=project/"99-专业工程"
        image_a=self.out/"first.png"
        image_b=self.out/"same-content.png"
        image_a.write_bytes(b"same test pixels")
        image_b.write_bytes(image_a.read_bytes())
        first=store_asset(engine,image_a,"image",1)
        second=store_asset(engine,image_b,"image",2)
        self.assertEqual(first,second)
        self.assertEqual(len(list((project/"02-媒体素材"/"图片").iterdir())),1)
        self.assertTrue(relative_media(engine,first).startswith("图片/"))

    def test_reported_pass_cannot_override_unverified_spoken_audio(self):
        p=self.new()
        d=p/"99-专业工程"
        script={"content_id":p.name,"title":"测试片","duration_seconds":3,
                "narration":"测试中的口播。","shots":[{"seconds":3,"visual":"画面","voiceover":"测试中的口播。"}],
                "platforms":{}}
        (d/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        (p/"成品视频.mp4").write_bytes(b"test fixture not a real video")
        import hashlib
        digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
        (d/"video").mkdir(exist_ok=True)
        (d/"video/render.json").write_text(json.dumps({
            "video_sha256":digest(p/"成品视频.mp4"),"script_sha256":digest(d/"script.json"),
            "render_status":"technical_only"}),encoding="utf8")
        (d/"video/review.json").write_text(json.dumps({
            "result":"PASS","pronunciation_check":{"result":"NOT_VERIFIED"},
            "checks":[{"result":"PASS"}],"issues":[],"facts_to_verify":[]}),encoding="utf8")
        response=self.call("status","--id",p.name)
        self.assertEqual(response.returncode,0,response.stderr)
        report=json.loads(response.stdout)
        self.assertEqual(report["delivery_verdict"]["speech"],"BLOCK")
        self.assertNotEqual(report["delivery_verdict"]["overall"],"PASS")
        self.assertTrue(report["delivery_verdict"]["inconsistent_review"])

    def test_v013_chinese_storyboard_without_video_field_is_still_editable(self):
        import hashlib
        p=self.new()
        d=p/"99-专业工程"
        script={"content_id":p.name,"title":"旧版中文工程","narration":"旧版文案。",
                "duration_seconds":3,"shots":[{"seconds":3,"visual":"旧镜头","voiceover":"旧版文案。"}],
                "platforms":{}}
        (d/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        self.assertEqual(self.call("storyboard","--id",p.name,"--from-engine").returncode,0)
        doc=p/"01-文案与分镜"/"分镜脚本.md"
        old=doc.read_text("utf8").replace("- 视频：无","")
        doc.write_text(old,encoding="utf8")
        meta_path=d/"user-storyboard.json"
        meta=json.loads(meta_path.read_text("utf8"))
        meta["md_sha256"]=hashlib.sha256(doc.read_bytes()).hexdigest()
        meta_path.write_text(json.dumps(meta,ensure_ascii=False),encoding="utf8")
        self.assertNotIn("- 视频",doc.read_text("utf8"))
        result=self.call("storyboard","--id",p.name,"--apply")
        self.assertEqual(result.returncode,0,result.stderr)
        updated=json.loads((d/"script.json").read_text("utf8"))
        self.assertEqual(updated["shots"][0]["visual"],"旧镜头")
        self.assertEqual(updated["duration_seconds"],3)

    def test_legacy_project_remains_untouched_and_readable(self):
        p=self.out/"oldcase"
        p.mkdir()
        (p/"content.json").write_text(json.dumps({"content_id":"oldcase","schema":3,"title":"Legacy"}),encoding="utf8")
        (p/"publish-ledger.json").write_text(json.dumps({"platforms":{}}),encoding="utf8")
        status=self.call("list")
        self.assertEqual(status.returncode,0,status.stderr)
        self.assertIn("oldcase",status.stdout)
        self.assertFalse((p/"99-专业工程").exists())

if __name__=="__main__":unittest.main()
