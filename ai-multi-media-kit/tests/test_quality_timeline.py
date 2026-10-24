"""Quality contract for continuous voice, timed subtitles and real-video source.

Run as normal unittest; external MP4 test is separately opt-in.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest
import wave

HERE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(HERE/"scripts"))
from quick_video import checked_spec


class TimelineQualityTests(unittest.TestCase):
    def setUp(self):
        t=tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.base=Path(t.name)
        self.wav=self.base/"full.wav"
        with wave.open(str(self.wav),"wb") as f:
            f.setnchannels(1);f.setsampwidth(2);f.setframerate(16000)
            f.writeframes(b"\0\0"*16000*6)
        self.specfile=self.base/"brief.json"
        self.spec={
            "title":"把一段资料变成视频",
            "audience":"视频创作者",
            "primary_value":"减少手工跨工具衔接",
            "narration_audio":str(self.wav),
            "subtitles_required":True,
            "subtitle_timing_source":"tts_word_boundary",
            "subtitles":[
                {"start":.3,"end":2.6,"text":"一个选题也能做视频，"},
                {"start":3.0,"end":5.4,"text":"视频制作不必反复搬运。"},
            ],
            "shots":[
                {"title":"选题开场","seconds":3.0,"caption":"痛点","voiceover":"一个选题也能做视频，"},
                {"title":"实际画面","seconds":3.0,"caption":"结果","voiceover":"视频制作不必反复搬运。"},
            ],
        }

    def check(self, data=None):
        return checked_spec(self.spec if data is None else data,self.specfile)

    def test_subtitle_edit_rejects_word_mismatch_and_updates_timing(self):
        from rebuild_video import review_subtitle_edits
        engine=self.base/"99-专业工程"
        engine.mkdir()
        scriptdir=self.base/"01-文案与分镜"
        scriptdir.mkdir()
        plan={"cues":self.spec["subtitles"],"required":True,
              "timing_source":"tts_word_boundary"}
        (engine/"subtitles.json").write_text(json.dumps(plan,ensure_ascii=False),encoding="utf8")
        srt=scriptdir/"字幕文件.srt"
        srt.write_text("1\n00:00:00,300 --> 00:00:02,600\n一个选题也能做视频，\n\n"
                       "2\n00:00:03,000 --> 00:00:05,400\n视频制作不必反复搬运。\n",encoding="utf8")
        voice=[{"voiceover":"一个选题也能做视频，"},{"voiceover":"视频制作不必反复搬运。"}]
        result=review_subtitle_edits(engine,voice,6)
        self.assertFalse(result["modified"])
        srt.write_text(srt.read_text("utf8").replace("00:00:03,000","00:00:03,300"),encoding="utf8")
        updated=review_subtitle_edits(engine,voice,6)
        self.assertTrue(updated["modified"])
        self.assertEqual(updated["plan"]["cues"][1]["start"],3.3)
        self.assertEqual(updated["plan"]["timing_source"],"manually_adjusted_needs_listening")
        srt.write_text(srt.read_text("utf8").replace("视频制作不必反复搬运","视频完全不需要制作"),encoding="utf8")
        with self.assertRaisesRegex(ValueError,"字幕.*口播"):
            review_subtitle_edits(engine,voice,6)

    def test_editable_srt_parses_real_timestamps_and_rejects_overlap(self):
        from quick_video import parse_srt
        file=self.base/"字幕.srt"
        file.write_text("1\n00:00:00,300 --> 00:00:02,600\n一个选题也能做视频，\n\n"
                        "2\n00:00:03,000 --> 00:00:05,400\n视频制作不必反复搬运。\n",encoding="utf8")
        cues=parse_srt(file)
        self.assertEqual(cues[0]["start"],.3)
        self.assertEqual(cues[-1]["end"],5.4)
        self.assertEqual("".join(c["text"] for c in cues),
                         "一个选题也能做视频，视频制作不必反复搬运。")
        file.write_text(file.read_text("utf8").replace("00:00:03,000","00:00:02,400"),encoding="utf8")
        with self.assertRaisesRegex(ValueError,"字幕"):
            parse_srt(file)

    def test_one_full_track_can_span_multiple_visual_shots(self):
        result=self.check()
        self.assertEqual(result["narration_audio"],self.wav)
        self.assertEqual(len(result["shots"]),2)
        self.assertEqual(len(result["subtitles"]),2)
        self.assertTrue(result["subtitles_required"])

    def test_missing_subtitles_are_not_faked_from_static_caption(self):
        case={**self.spec,"subtitles":[]}
        with self.assertRaisesRegex(ValueError,"字幕"):
            self.check(case)

    def test_subtitles_must_cover_spoken_words_in_order(self):
        case={**self.spec,"subtitles":[{"start":.3,"end":4.3,"text":"一个选题也能做视频，"}]}
        with self.assertRaisesRegex(ValueError,"字幕.*口播|口播.*字幕"):
            self.check(case)

    def test_subtitle_intervals_cannot_overlap_or_run_past_audio(self):
        for malformed in [
            [{"start":0,"end":3.6,"text":"一个选题也能做视频，"},{"start":3.5,"end":5.4,"text":"视频制作不必反复搬运。"}],
            [{"start":0,"end":2.6,"text":"一个选题也能做视频，"},{"start":5.5,"end":6.8,"text":"视频制作不必反复搬运。"}],
        ]:
            with self.subTest(malformed=malformed),self.assertRaisesRegex(ValueError,"字幕"):
                self.check({**self.spec,"subtitles":malformed})

    def test_no_unverified_time_source_disguised_as_word_sync(self):
        with self.assertRaisesRegex(ValueError,"时间来源"):
            self.check({**self.spec,"subtitle_timing_source":"guessed_by_character_count"})

    def test_master_track_and_per_shot_audio_are_mutually_exclusive(self):
        shots=[dict(s) for s in self.spec["shots"]]
        shots[0]["audio"]=str(self.wav)
        with self.assertRaisesRegex(ValueError,"连续.*逐镜头"):
            self.check({**self.spec,"shots":shots})

    def test_video_footage_and_image_same_shot_rejected(self):
        image=self.base/"scene.svg"
        image.write_text('<svg xmlns="http://www.w3.org/2000/svg"/>',encoding="utf8")
        shots=[dict(s) for s in self.spec["shots"]]
        shots[0]["image"]=str(image)
        shots[0]["video"]="sample.mp4"
        with self.assertRaisesRegex(ValueError,"图片.*视频|视频.*图片"):
            self.check({**self.spec,"shots":shots})

    def test_long_gap_warns_without_claiming_natural_pacing(self):
        import array
        from media_audio import assess_pcm
        samples=array.array("h",([8000]*750)+([0]*1600)+([8000]*650))
        result=assess_pcm(samples.tobytes(),1000,[{"seconds":3,"voiceover":"完整句子"}])
        self.assertEqual(result["result"],"PASS")
        self.assertTrue(result["pacing_warnings"])
        self.assertGreaterEqual(result["pacing_warnings"][0]["silence_seconds"],1.2)

    @unittest.skipUnless(__import__("os").environ.get("AI_MEDIA_TEST_FFMPEG"),
                         "Real FFmpeg required for full workflow")
    def test_studio_continuous_voiceover_uses_ready_whole_sentence(self):
        import os
        import subprocess
        ffmpeg=os.environ["AI_MEDIA_TEST_FFMPEG"]
        install=self.base/"run_tools"
        kb=self.base/"run_knowledge"
        dest=self.base/"run_results"
        (install/"config").mkdir(parents=True)
        kb.mkdir();dest.mkdir()
        (kb/"review-rules.md").write_text("Check actual facts.",encoding="utf8")
        (install/"config/workspace.json").write_text(json.dumps({
            "install_root":str(install),"knowledge_root":str(kb),"output_root":str(dest)}
        ),encoding="utf8")
        args=[sys.executable,"-X","utf8",str(HERE/"scripts/studio.py"),"--root",str(install)]
        def run(*params):
            return subprocess.run([*args,*params],capture_output=True,text=True,encoding="utf8",timeout=60)
        creation=run("new","--topic","continuous","--agent","codex","--title","测试连续语音")
        self.assertEqual(creation.returncode,0,creation.stderr)
        project=next(x for x in dest.iterdir() if x.is_dir())
        engine=project/"99-专业工程"
        script={"content_id":project.name,"title":"测试连续语音",
                "narration":"一句开始。一句收尾。",
                "duration_seconds":6,"shots":[
                  {"seconds":3,"visual":"片段一","voiceover":"一句开始。"},
                  {"seconds":3,"visual":"片段二","voiceover":"一句收尾。"}],
                "platforms":{},"editorial_intent":{"audience":"个人创作者",
                    "primary_value":"视频自动生产","secondary_values":[],"evidence_plan":["隔离合成音频"]}}
        (engine/"script.json").write_text(json.dumps(script,ensure_ascii=False),encoding="utf8")
        plan=run("speech-plan","--id",project.name,"--tts-engine","local-test","--voice","synthetic-tone")
        self.assertEqual(plan.returncode,0,plan.stderr)
        from pathlib import Path
        full=list((engine/"work/tts-inputs").rglob("完整连续口播.txt"))
        self.assertEqual(len(full),1)
        self.assertEqual(full[0].read_text("utf8"),"一句开始。一句收尾。")
        sine=self.base/"wav.wav"
        make=subprocess.run([ffmpeg,"-v","error","-f","lavfi","-i",
            "sine=frequency=480:duration=6:sample_rate=48000",
            "-c:a","pcm_s16le","-y",str(sine)],capture_output=True,timeout=30)
        self.assertEqual(make.returncode,0,make.stderr)
        one=run("voiceover","--id",project.name,"--continuous","--takes",str(sine))
        self.assertEqual(one.returncode,0,one.stderr)
        output=project/"02-媒体素材"/"配音"/"完整旁白.wav"
        self.assertTrue(output.is_file())
        meta=json.loads((engine/"work/voiceover-check.json").read_text("utf8"))
        self.assertEqual(meta["mode"],"continuous")
        self.assertEqual(meta["result"],"PASS")

    @unittest.skipUnless(__import__("os").environ.get("AI_MEDIA_TEST_FFMPEG"),
                         "Requires existing system FFmpeg")
    def test_continuous_assembly_preserves_audio_across_visual_cuts(self):
        import os
        from media_audio import mix_continuous
        ffmpeg=os.environ["AI_MEDIA_TEST_FFMPEG"]
        ffprobe=os.environ.get("AI_MEDIA_TEST_FFPROBE")
        if not ffprobe:self.skipTest("FFprobe is not configured")
        original=self.base/"full-recording.wav"
        result=__import__("subprocess").run([ffmpeg,"-v","error","-f","lavfi","-i",
            "sine=frequency=480:duration=6:sample_rate=48000","-c:a","pcm_s16le",
            "-y",str(original)],capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        target=self.base/"assembled.wav"
        report=mix_continuous(ffmpeg,ffprobe,[{"seconds":3,"voiceover":"前半句"},
                                             {"seconds":3,"voiceover":"后半句"}],original,target)
        self.assertEqual(report["result"],"PASS")
        self.assertEqual(report["mode"],"continuous")
        import wave
        with wave.open(str(target),"rb") as w:
            w.setpos(round(2.99*w.getframerate()))
            fragment=w.readframes(round(.02*w.getframerate()))
            self.assertGreater(max(abs(x) for x in __import__("array").array("h",fragment)),500)

    @unittest.skipUnless(__import__("os").environ.get("AI_MEDIA_QUICK_REAL_RENDER")=="1",
                         "Explicit real Remotion end-to-end requested")
    def test_real_continuous_voice_and_timed_subtitles_cross_scene_boundary(self):
        import os
        import shutil
        ffmpeg=shutil.which("ffmpeg")
        probe=shutil.which("ffprobe")
        if not ffmpeg or not probe or not shutil.which("npx"):
            self.skipTest("Local FFmpeg, FFprobe and Node toolchain required")
        raw=self.base/"spoken.wav"
        video=self.base/"actual-sequence.mp4"
        for cmd in [
            [ffmpeg,"-v","error","-f","lavfi","-i","sine=frequency=560:duration=6:sample_rate=48000",
             "-ac","1","-c:a","pcm_s16le","-y",str(raw)],
            [ffmpeg,"-v","error","-f","lavfi","-i","color=c=royalblue:s=320x570:r=30:d=3.1",
             "-c:v","libx264","-pix_fmt","yuv420p","-y",str(video)]
        ]:
            r=__import__("subprocess").run(cmd,capture_output=True,timeout=35)
            self.assertEqual(r.returncode,0,r.stderr)
        task={**self.spec,"narration_audio":str(raw)}
        task["shots"]=[dict(item) for item in self.spec["shots"]]
        task["shots"][0]["video"]=str(video)
        self.specfile.write_text(json.dumps(task,ensure_ascii=False),encoding="utf8")
        install=self.base/"install"
        kb=self.base/"knowledge"
        out=self.base/"delivery"
        (install/"config").mkdir(parents=True)
        kb.mkdir();out.mkdir()
        (kb/"review-rules.md").write_text("No false claims.",encoding="utf8")
        (install/"config/workspace.json").write_text(json.dumps({
            "install_root":str(install),"knowledge_root":str(kb),"output_root":str(out)
        }),encoding="utf8")
        run=__import__("subprocess").run([sys.executable,"-X","utf8",str(HERE/"scripts/studio.py"),"--root",str(install),
            "quick","--spec",str(self.specfile),"--topic","continuous","--agent","codex"],
            capture_output=True,text=True,encoding="utf8",errors="replace",timeout=600)
        self.assertEqual(run.returncode,0,run.stderr[-2400:])
        project=next(x for x in out.iterdir() if x.is_dir())
        engine=project/"99-专业工程"
        mp4=project/"成品视频.mp4"
        self.assertGreater(mp4.stat().st_size,5000)
        render=json.loads((engine/"video/render.json").read_text("utf8"))
        self.assertEqual(render["subtitles_status"],"timed")
        self.assertEqual(render["render_status"],"technical_only")
        self.assertTrue((project/"01-文案与分镜/字幕文件.srt").is_file())
        self.assertEqual(len(list((project/"02-媒体素材/视频片段").glob("*.mp4"))),1)
        self.assertEqual(len(list((project/"02-媒体素材/配音").glob("*.wav"))),1)
        manifest=json.loads((engine/"shotlist.json").read_text("utf8"))
        self.assertTrue(manifest["narration_audio"].startswith("配音/"))
        self.assertEqual(len(json.loads((engine/"subtitles.json").read_text("utf8"))["cues"]),2)
        # Audio is continuous: the visual cut at exactly 3 s must not introduce silence.
        check=__import__("subprocess").run([ffmpeg,"-hide_banner","-ss","2.85","-t","0.3","-i",str(mp4),
            "-map","0:a:0","-af","volumedetect","-f","null","-"],capture_output=True,
            text=True,encoding="utf8",errors="replace",timeout=30)
        self.assertEqual(check.returncode,0,check.stderr[-800:])
        import re
        volume=re.search(r"mean_volume:\s*(-?\d+(?:\.\d+)?) dB",check.stderr)
        self.assertIsNotNone(volume,check.stderr[-1000:])
        self.assertGreater(float(volume.group(1)),-55)
        board=project/"01-文案与分镜"/"分镜脚本.md"
        original_board=board.read_text("utf8")
        board.write_text(original_board.replace("一个选题也能做视频，","完全不同的一句话，"),encoding="utf8")
        refuse=__import__("subprocess").run([sys.executable,"-X","utf8",str(HERE/"scripts/studio.py"),
            "--root",str(install),"rebuild","--id",project.name,"--dry-run"],
            capture_output=True,text=True,encoding="utf8",errors="replace",timeout=30)
        self.assertNotEqual(refuse.returncode,0)
        self.assertIn("旧连续配音",refuse.stderr)
        board.write_text(original_board,encoding="utf8")
        srt=project/"01-文案与分镜"/"字幕文件.srt"
        srt.write_text(srt.read_text("utf8").replace("00:00:03,000","00:00:03,200"),encoding="utf8")
        rerender=__import__("subprocess").run([sys.executable,"-X","utf8",str(HERE/"scripts/studio.py"),
            "--root",str(install),"rebuild","--id",project.name],
            capture_output=True,text=True,encoding="utf8",errors="replace",timeout=600)
        self.assertEqual(rerender.returncode,0,rerender.stderr[-2400:])
        self.assertEqual(json.loads((engine/"subtitles.json").read_text("utf8"))["cues"][1]["start"],3.2)
        self.assertTrue(list((project/"03-修改与版本").glob("旧成片-*.mp4")))
        record=json.loads((engine/"video/render.json").read_text("utf8"))
        import hashlib
        self.assertEqual(record["video_sha256"],hashlib.sha256(mp4.read_bytes()).hexdigest())
        self.assertEqual(record["subtitle_file_sha256"],hashlib.sha256(srt.read_bytes()).hexdigest())

    def test_legacy_quick_without_timed_cues_stays_technical_only(self):
        case={**self.spec}
        del case["narration_audio"],case["subtitles"],case["subtitle_timing_source"],case["subtitles_required"]
        result=self.check(case)
        self.assertFalse(result["subtitles"])
        self.assertIsNone(result["narration_audio"])


if __name__=="__main__":
    unittest.main()
