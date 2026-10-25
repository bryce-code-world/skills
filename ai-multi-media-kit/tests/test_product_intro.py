"""Named-product intro must not degrade into generic AI promo."""
from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(HERE/"scripts"))
from quick_video import checked_spec


class NamedProductTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/"topic.json"
        (self.path.parent/"intro.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>\n',encoding="utf8")
        self.intro={
            "title":"从一个选题到一条视频",
            "video_purpose":"product_intro",
            "subject_name":"ai-multi-media-kit",
            "subject_spoken":"AI Multi Media Kit",
            "audience":"个人内容创作者",
            "primary_value":"让 Agent 衔接配音、素材、字幕、成片和修改",
            "shots":[
                {"title":"AI 写完文案，视频还没做好？",
                 "seconds":6,"voiceover":"AI 会写文案，但找素材、录音、剪辑还是靠自己。"},
                {"title":"ai-multi-media-kit 来了",
                 "seconds":6,"image":str(self.path.parent/"intro.svg"),
                 "voiceover":"AI Multi Media Kit 就是帮创作者衔接这些步骤的工具。"},
                {"title":"实际制作展示",
                 "seconds":6,"voiceover":"给一个主题，Agent 就能组织一条可以修改的视频。"},
                {"title":"试试 ai-multi-media-kit",
                 "seconds":5,"voiceover":"用 AI Multi Media Kit，把想法变成可编辑的视频。"},
            ]
        }

    def checked(self,patch=None):
        return checked_spec(patch if patch is not None else self.intro,self.path)

    def test_product_intro_must_state_its_named_subject(self):
        x={**self.intro}
        x.pop("subject_name")
        with self.assertRaisesRegex(ValueError,"产品名称|介绍对象"):
            self.checked(x)

    def test_named_product_must_appear_in_visible_title_early(self):
        x={**self.intro,"shots":[dict(s) for s in self.intro["shots"]]}
        x["shots"][1]["title"]="一键串起各种流程"
        with self.assertRaisesRegex(ValueError,"产品名称.*画面|开头.*画面"):
            self.checked(x)

    def test_brand_in_second_shot_after_long_silent_opening_is_too_late(self):
        from copy import deepcopy
        value=deepcopy(self.intro)
        value["shots"][0]["seconds"]=18
        value["shots"][0]["image"]=str(self.path.parent/"intro.svg")
        with self.assertRaisesRegex(ValueError,"开头.*秒|提前"):
            self.checked(value)

    def test_named_product_must_be_spoken_early(self):
        x={**self.intro,"shots":[dict(s) for s in self.intro["shots"]]}
        x["shots"][1]["voiceover"]="现在有工具能够把视频环节串起来。"
        with self.assertRaisesRegex(ValueError,"口播.*产品名称|口播.*介绍对象"):
            self.checked(x)

    def test_name_only_in_the_closing_is_too_late(self):
        x={**self.intro,"shots":[dict(s) for s in self.intro["shots"]]}
        x["shots"][1]["title"]="让制作更简单"
        x["shots"][1]["voiceover"]="使用工具实现自动化视频生产。"
        with self.assertRaisesRegex(ValueError,"开头|画面|口播"):
            self.checked(x)

    def test_final_scene_returns_to_subject_name(self):
        x={**self.intro,"shots":[dict(s) for s in self.intro["shots"]]}
        x["shots"][-1]["title"]="从想法到视频"
        x["shots"][-1]["voiceover"]="把你的想法变成作品吧。"
        with self.assertRaisesRegex(ValueError,"结尾.*产品名称"):
            self.checked(x)

    def test_valid_intro_records_subject_for_render_and_human_brief(self):
        validated=self.checked()
        self.assertEqual(validated["video_purpose"],"product_intro")
        self.assertEqual(validated["subject_name"],"ai-multi-media-kit")
        self.assertEqual(validated["subject_spoken"],"AI Multi Media Kit")

    def test_non_product_video_does_not_require_branding(self):
        other={**self.intro}
        for key in ("video_purpose","subject_name","subject_spoken"):
            other.pop(key)
        out=self.checked(other)
        self.assertEqual(out["video_purpose"],"general")
        self.assertIsNone(out["subject_name"])


if __name__=="__main__":
    unittest.main()
