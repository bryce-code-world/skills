"""Caption safe-area geometry for programmatic 9:16 layouts."""
from __future__ import annotations
import sys
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))


class SubtitleLayoutTests(unittest.TestCase):
    def test_separate_caption_band_passes(self):
        from subtitle_layout import inspect_layout
        report = inspect_layout(1080, 1920,
                                content_boxes=[(90, 200, 980, 1320)],
                                subtitle_boxes=[(90, 1480, 990, 1710)])
        self.assertEqual(report["result"], "PASS", report)

    def test_realistic_workbuddy_lower_body_is_blocked(self):
        from subtitle_layout import inspect_layout
        report = inspect_layout(1080, 1920,
                                content_boxes=[(90, 1400, 1000, 1510)],
                                subtitle_boxes=[(70, 1480, 1010, 1650)])
        self.assertEqual(report["result"], "BLOCK")
        self.assertTrue(any("正文" in s or "重叠" in s for s in report["issues"]))

    def test_trae_phone_card_cannot_be_behind_caption(self):
        from subtitle_layout import inspect_layout
        report = inspect_layout(1080, 1920,
                                content_boxes=[(160, 1420, 530, 1830)],
                                subtitle_boxes=[(110, 1550, 960, 1690)])
        self.assertEqual(report["result"], "BLOCK")

    def test_caption_overflow_and_two_line_height_checked(self):
        from subtitle_layout import inspect_layout
        report = inspect_layout(1080, 1920,
                                content_boxes=[(90, 200, 980, 1320)],
                                subtitle_boxes=[(10, 1490, 1070, 1900)])
        self.assertEqual(report["result"], "BLOCK")
        self.assertTrue(any("越界" in s or "安全区" in s for s in report["issues"]))

    def test_cli_checks_all_shots_and_reports_declared_geometry_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'layout.json'
            layout={'width':1080, 'height':1920, 'shots':[{
                'content_boxes':[[90,200,980,1300]],
                'subtitle_boxes':[[90,1500,990,1680]]}]}
            path.write_text(json.dumps(layout),encoding='utf8')
            args=[sys.executable,'-X','utf8',str(Path(__file__).resolve().parents[1]/
                  'scripts/subtitle_layout.py'),'--layout',str(path)]
            passed=subprocess.run(args,capture_output=True,text=True,encoding='utf8',timeout=10)
            self.assertEqual(passed.returncode,0,passed.stderr)
            self.assertIn('renderer_declared_boxes_not_video_vision',passed.stdout)
            layout['shots'][0]['content_boxes']=[[90,1400,980,1500]]
            path.write_text(json.dumps(layout),encoding='utf8')
            blocked=subprocess.run(args,capture_output=True,text=True,encoding='utf8',timeout=10)
            self.assertEqual(blocked.returncode,2,blocked.stdout)
            self.assertIn('字幕',blocked.stdout)

    def test_image_bounds_must_be_valid(self):
        from subtitle_layout import inspect_layout
        with self.assertRaises(ValueError):
            inspect_layout(1080, 1920, content_boxes=[(100, 100, 80, 200)],
                           subtitle_boxes=[(90, 1490, 990, 1600)])


if __name__ == "__main__":
    unittest.main()
