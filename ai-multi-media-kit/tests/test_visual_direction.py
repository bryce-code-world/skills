"""Visual direction contract: useful defaults, no fabricated evidence.

Nothing here requires third-party stock, a new model API or sound-effects bundle.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
from quick_video import checked_spec


class VisualDirectionTests(unittest.TestCase):
    def setUp(self):
        task=tempfile.TemporaryDirectory()
        self.addCleanup(task.cleanup)
        self.root=Path(task.name)
        self.brief=self.root/"brief.json"
        self.frame=self.root/"real-demo.svg"
        self.frame.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="900">'
                              '<rect width="640" height="900" fill="#006878"/></svg>',encoding="utf8")
        self.before=self.root/"before.svg"
        self.before.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="900">'
                               '<rect width="640" height="900" fill="#B26072"/></svg>',encoding="utf8")
        self.after=self.root/"after.svg"
        self.after.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="900">'
                              '<rect width="640" height="900" fill="#408E7E"/></svg>',encoding="utf8")
        self.raw={
            "title":"整理一条视频",
            "audience":"手机短视频个人创作者",
            "primary_value":"用真实演示讲清楚结果",
            "aspect":"9:16",
            "shots":[{"title":"为什么素材还要自己整理？","seconds":3,
                      "voiceover":"为什么素材还要自己整理？","image":str(self.frame)}]
        }

    def check(self,value=None):
        return checked_spec(self.raw if value is None else value,self.brief)

    def test_default_director_selects_visual_style_and_mode(self):
        result=self.check()
        self.assertEqual(result["visual_style"],"social")
        self.assertEqual(result["shots"][0]["visual_mode"],"focus")
        self.assertEqual(result["shots"][0]["visual_intent"],"problem")
        self.assertEqual(result["shots"][0]["direction_source"],"inferred")

    def test_clear_explicit_direction_and_style_take_precedence(self):
        custom={**self.raw,"visual_style":"warm"}
        custom["shots"]=[{**self.raw["shots"][0],"visual_intent":"evidence","visual_mode":"showcase"}]
        result=self.check(custom)
        self.assertEqual(result["visual_style"],"warm")
        self.assertEqual(result["shots"][0]["visual_mode"],"showcase")
        self.assertEqual(result["shots"][0]["direction_source"],"explicit")

    def test_all_six_selectable_original_modes(self):
        self.assertEqual(set(("focus","showcase","kinetic","reveal","compare","steps")),
                         set(__import__("quick_video").DIRECTOR_MODES)-{"standard"})
        for mode in ("focus","showcase","reveal","kinetic"):
            with self.subTest(mode=mode):
                value={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":mode}]}
                self.assertEqual(self.check(value)["shots"][0]["visual_mode"],mode)
        value={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":"compare",
                                   "before_image":str(self.before),"after_image":str(self.after)}]}
        self.assertEqual(self.check(value)["shots"][0]["visual_mode"],"compare")
        value={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":"steps",
                                   "steps":["收集","分类","复习"]}]}
        self.assertEqual(self.check(value)["shots"][0]["visual_mode"],"steps")

    def test_no_synthetic_before_after_evidence(self):
        value={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":"compare"}]}
        with self.assertRaisesRegex(ValueError,"对比.*前后|前后.*对比"):
            self.check(value)
        other={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":"compare",
                                   "before_image":str(self.frame),"after_image":str(self.frame)}]}
        with self.assertRaisesRegex(ValueError,"相同|不同"):
            self.check(other)

    def test_steps_must_not_invent_instruction_text(self):
        value={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":"steps"}]}
        with self.assertRaisesRegex(ValueError,"步骤|steps"):
            self.check(value)
        invalid={**self.raw,"shots":[{**self.raw["shots"][0],"visual_mode":"steps",
                                     "steps":["采集", "分析", "合成", "发布"]}]}
        with self.assertRaisesRegex(ValueError,"步骤|steps"):
            self.check(invalid)

    def test_invalid_styles_and_modes_reject_before_creating_project(self):
        with self.assertRaisesRegex(ValueError,"视觉风格"):
            self.check({**self.raw,"visual_style":"cinematic-premium"})
        shot={**self.raw["shots"][0],"visual_mode":"shaky_3d_camera"}
        with self.assertRaisesRegex(ValueError,"镜头"):
            self.check({**self.raw,"shots":[shot]})

    def test_old_projects_can_force_standard_mode(self):
        test={**self.raw,"visual_style":"product","shots":[
            {**self.raw["shots"][0],"visual_mode":"standard"}]}
        result=self.check(test)
        self.assertEqual(result["shots"][0]["visual_mode"],"standard")
        self.assertEqual(result["visual_style"],"product")

    def test_visual_selector_never_claims_real_footage_from_keyword(self):
        item={**self.raw["shots"][0],"title":"真实效果演示","image":None}
        result=self.check({**self.raw,"shots":[item]})
        self.assertNotEqual(result["shots"][0]["visual_mode"],"compare")
        self.assertEqual(result["shots"][0]["before_image"],None)
        self.assertEqual(result["shots"][0]["after_image"],None)


if __name__=="__main__":
    unittest.main()
