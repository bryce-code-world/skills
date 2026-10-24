"""Creator identity, shared topics and pronunciation preparation. Offline, isolated."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(SOURCE/'scripts'))


class IdentitySpeechTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.skill = self.base / 'skill'
        shutil.copytree(SOURCE, self.skill, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'local-install.json'))
        self.root, self.kb, self.output = [self.base / x for x in ('tools', 'knowledge', 'project output')]
        self.env = dict(os.environ, LOCALAPPDATA=str(self.base/'local'), XDG_CONFIG_HOME=str(self.base/'xdg'))
        p = self.run_cli('init_workspace.py', '--install-root', self.root, '--knowledge-root', self.kb,
                         '--output-root', self.output)
        self.assertEqual(p.returncode, 0, p.stderr)

    def run_cli(self, file, *args):
        return subprocess.run([sys.executable, '-X', 'utf8', str(self.skill/'scripts'/file), *map(str, args)],
            capture_output=True, text=True, encoding='utf8', errors='replace', env=self.env, timeout=35)

    def call(self, *args):
        return self.run_cli('studio.py', '--root', self.root, *args)

    def new(self, agent='workbuddy', run='r1', *args):
        p = self.call('new', '--topic', 'intro', '--agent', agent, '--run-id', run,
                      '--title', '从主题到视频的自动化流程', *args)
        self.assertEqual(p.returncode, 0, p.stderr)
        cid=next(line.split('=',1)[1] for line in p.stdout.splitlines() if line.startswith('CONTENT_ID='))
        return self.output/cid

    def script(self, d, text='告诉助手一个主题，就能开始制作视频。'):
        data = {'content_id': d.name, 'title': '从主题到视频的自动化流程', 'duration_seconds': 5,
            'narration': text, 'shots': [{'seconds': 5, 'voiceover': text, 'subtitle_text': text, 'visual': '实际制作过程'}],
            'editorial_intent': {'audience': '内容创作者', 'primary_value': '视频自动化生产',
                'secondary_values': ['跨宿主使用'], 'evidence_plan': ['展示主题生成脚本和成片的过程']},
            'platforms': {k: {'title': '从主题到视频', 'tags': []} for k in
                ('xiaohongshu','douyin','tencent','bilibili','kuaishou','wechat_oa','zhihu')}}
        self.write(d/'99-专业工程/script.json', data)
        return data

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf8')

    def plan(self, d, *args):
        return self.call('speech-plan', '--id', d.name, '--tts-engine', 'edge-tts', '--voice', 'test-voice', *args)

    def test_same_topic_separate_agents_and_list_filter(self):
        a, b = self.new(), self.new('trae', 'r1', '--model', 'test-model')
        for d, agent in ((a,'workbuddy'),(b,'trae')):
            data=json.loads((d/'99-专业工程/content.json').read_text('utf8'))
            self.assertEqual(data['topic_id'], 'intro')
            self.assertEqual(data['agent_id'], agent)
            self.assertEqual(data['run_id'], 'r1')
            self.assertEqual(data['schema'], 4)
        self.assertIsNone(json.loads((a/'99-专业工程/content.json').read_text('utf8'))['model_id'])
        self.assertEqual(json.loads((b/'99-专业工程/content.json').read_text('utf8'))['model_id'],'test-model')
        p=self.call('list','--topic','intro')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual({x['agent_id'] for x in json.loads(p.stdout)['items']},{'trae','workbuddy'})
        self.assertEqual(json.loads(self.call('list','--topic','other').stdout)['items'],[])

    def test_model_slug_appears_in_folder_but_original_model_preserved(self):
        d = self.new('trae', 'r2', '--model', 'MiMo-V2.6-Flash')
        self.assertEqual(d.name, 'intro-trae-mimo-v2-6-flash-r2')
        data=json.loads((d/'99-专业工程/content.json').read_text('utf8'))
        self.assertEqual(data['model_id'], 'MiMo-V2.6-Flash')
        self.assertEqual(data['model_slug'], 'mimo-v2-6-flash')

    def test_missing_model_is_labeled_unknown_in_folder_not_invented(self):
        d=self.new()
        self.assertEqual(d.name, 'intro-workbuddy-model-unknown-r1')
        data=json.loads((d/'99-专业工程/content.json').read_text('utf8'))
        self.assertIsNone(data['model_id'])
        self.assertEqual(data['model_slug'], 'model-unknown')

    def test_distinct_long_models_truncate_with_hash_and_preserve_source(self):
        from content_identity import new_identity
        from types import SimpleNamespace
        common={'topic':'amk-workflow-intro', 'agent':'workbuddy', 'id':None,
                'run_id':'202610172023-ab123','parent_id':None}
        models=['Claude Sonnet 4.5 - Optimized-Alpha', 'Claude Sonnet 4.5 - Optimized-Beta']
        ids=[]
        for raw in models:
            result=new_identity(SimpleNamespace(**common, model=raw))
            self.assertLessEqual(len(result['content_id']),64)
            self.assertEqual(result['model_id'],raw)
            self.assertIn('workbuddy-',result['content_id'])
            ids.append(result['content_id'])
        self.assertNotEqual(ids[0],ids[1])

    def test_auto_run_ids_are_unique_and_keep_agent_in_path(self):
        for _ in range(2):
            p=self.call('new','--topic','intro','--agent','codex','--title','自动生成独立运行号')
            self.assertEqual(p.returncode,0,p.stderr)
        dirs=list(self.output.glob('intro-codex-*'))
        self.assertEqual(len(dirs),2)
        self.assertNotEqual(dirs[0].name,dirs[1].name)
        self.assertTrue(all(len(d.name)<=64 for d in dirs))

    def test_collision_bad_identity_and_parent_do_not_touch_previous_content(self):
        d=self.new(); before=(d/'99-专业工程/content.json').read_bytes()
        collision=self.call('new','--topic','intro','--agent','workbuddy','--run-id','r1','--title','不能覆盖前一作品')
        self.assertEqual(collision.returncode,2)
        for args in [('--agent','../x','--topic','intro'),('--agent','workbuddy'),
                     ('--id','unnamed','--agent','workbuddy'),
                     ('--topic','intro','--agent','trae','--parent-id','missing')]:
            self.assertEqual(self.call('new','--title','无效的创作归属',*args).returncode,2)
        self.assertEqual((d/'99-专业工程/content.json').read_bytes(),before)
        self.assertEqual(len(list(self.output.iterdir())),1)

    def test_fork_records_parent_hash_without_changing_parent(self):
        source=self.new(); self.script(source)
        before=(source/'99-专业工程/script.json').read_bytes()
        child=self.new('codex','r2','--parent-id',source.name)
        parent=json.loads((child/'99-专业工程/content.json').read_text('utf8'))['parent']
        self.assertEqual(parent['content_id'],source.name)
        self.assertIn('script_sha256',parent)
        self.assertEqual((source/'99-专业工程/script.json').read_bytes(),before)
        self.assertFalse((child/'99-专业工程/script.json').exists())

    def test_legacy_id_readable_but_creator_not_invented(self):
        p=self.call('new','--id','old-001','--title','兼容旧的调用方式')
        self.assertEqual(p.returncode,0,p.stderr)
        info=json.loads(self.call('list').stdout)['items'][0]
        self.assertEqual(info['content_id'],'old-001')
        self.assertEqual(info['agent_id'],'unknown')
        self.assertIsNone(info['model_id'])

    def test_pronunciation_risk_blocks_until_agent_rewrites_all_texts(self):
        d=self.new(); self.script(d,'不用重复配置，就能开始制作视频。')
        p=self.plan(d)
        self.assertEqual(p.returncode,2,p.stdout)
        report=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        self.assertEqual(report['result'],'REVISE')
        self.assertEqual(report['findings'][0]['term'],'重复')
        self.assertEqual(report['findings'][0]['expected_reading'],'chong2 fu4')
        self.assertFalse(report['pronunciation_verified'])
        self.script(d,'不用反复配置，就能开始制作视频。')
        p=self.plan(d,'--replace')
        self.assertEqual(p.returncode,0,p.stderr)
        report=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        self.assertEqual(report['result'],'READY')
        self.assertEqual(report['tts_engine'],'edge-tts')
        textfile=d/'99-专业工程'/report['takes'][0]['text_file']
        self.assertEqual(textfile.read_text('utf8'),'不用反复配置，就能开始制作视频。')
        self.assertFalse(report['pronunciation_verified'])

    def test_user_lexicon_and_stale_plan_inputs_are_detected(self):
        d=self.new(); self.script(d)
        self.assertEqual(self.plan(d).returncode,0)
        self.write(self.kb/'pronunciation.json',{'schema':1,'terms':[{
            'term':'助手','expected_reading':'zhu4 shou3','suggestion':'核对实际音频'}]})
        bad=self.call('voiceover','--id',d.name,'--takes',self.base/'not-needed.wav')
        self.assertEqual(bad.returncode,2)
        self.assertIn('发音',bad.stderr)
        report=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        (d/'99-专业工程'/report['takes'][0]['text_file']).write_text('被其他Agent改写',encoding='utf8')
        bad=self.call('voiceover','--id',d.name,'--takes',self.base/'not-needed.wav')
        self.assertEqual(bad.returncode,2)

    def test_subtitles_and_narration_cannot_diverge_from_spoken_script(self):
        d=self.new(); data=self.script(d)
        data['shots'][0]['subtitle_text']='字幕与配音不一致。'; self.write(d/'99-专业工程/script.json',data)
        p=self.plan(d)
        self.assertEqual(p.returncode,2)
        self.assertIn('字幕',p.stderr)
        data['shots'][0]['subtitle_text']=data['narration'];data['narration']='另一版旁白。'
        self.write(d/'99-专业工程/script.json',data)
        self.assertEqual(self.plan(d).returncode,2)

    def test_tts_rejects_internal_layout_breaks_but_preserves_semantic_spaces(self):
        d=self.new()
        for separator in ('\n', '\r\n', '\t'):
            with self.subTest(separator=repr(separator)):
                data=self.script(d,'逐镜头配音按真实时长排进时间轴。')
                data['shots'][0]['voiceover']='逐镜头配音按真实时'+separator+'长排进时间轴。'
                self.write(d/'99-专业工程/script.json',data)
                p=self.plan(d)
                self.assertEqual(p.returncode,2)
                self.assertIn('内部换行或制表符',p.stderr)
                self.assertFalse((d/'99-专业工程/work/speech-plan.json').exists())
        self.script(d,' \n请用 AI Agent 制作视频。\t\n')
        p=self.plan(d)
        self.assertEqual(p.returncode,0,p.stderr)
        plan=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        self.assertEqual((d/'99-专业工程'/plan['takes'][0]['text_file']).read_text('utf8'),'请用 AI Agent 制作视频。')

    def test_speech_plan_needs_no_platforms_and_package_names_missing_target(self):
        d=self.new();data=self.script(d)
        self.assertEqual(json.loads((d/'99-专业工程/script.template.json').read_text('utf8'))['platforms'],{})
        data.pop('platforms');self.write(d/'99-专业工程/script.json',data)
        p=self.plan(d)
        self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('package','--id',d.name,'--platform','douyin')
        self.assertEqual(p.returncode,2)
        self.assertIn('平台 douyin 缺少 title 或 tags',p.stderr)
        self.assertNotIn('Traceback',p.stderr)
        data['platforms']={'douyin':{'title':'从主题到视频','tags':[]}}
        self.write(d/'99-专业工程/script.json',data)
        p=self.plan(d,'--replace')
        self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('package','--id',d.name,'--platform','zhihu')
        self.assertEqual(p.returncode,2)
        self.assertIn('平台 zhihu 缺少 title 或 tags',p.stderr)
        self.assertFalse((d/'99-专业工程/platforms').exists())
        data['platforms']['zhihu']={'title':'实际任务的内容结果','tags':[]}
        data['platforms']['douyin']['title']=''  # An unrelated draft is not a prerequisite.
        data['article_markdown']='# 本次内容\n原始文章测试夹具。'
        self.write(d/'99-专业工程/script.json',data)
        hashes=json.loads(self.call('hash','--id',d.name).stdout)
        self.write(d/'99-专业工程/review.json',{**hashes,'result':'PASS','checks':[{'result':'PASS','rule':'测试夹具'}],
            'facts_to_verify':[],'issues':[],
            'focus_alignment':{'result':'PASS','reason':'测试夹具验证单个平台包的结构边界。'}})
        p=self.call('package','--id',d.name,'--platform','zhihu')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(json.loads((d/'99-专业工程/platforms/zhihu/package.json').read_text('utf8'))['title'],'实际任务的内容结果')
        self.assertFalse((d/'99-专业工程/platforms/douyin').exists())

    @unittest.skipUnless((os.environ.get('AI_MEDIA_TEST_FFMPEG') or shutil.which('ffmpeg')) and
                         (os.environ.get('AI_MEDIA_TEST_FFPROBE') or shutil.which('ffprobe')), 'FFmpeg not installed')
    def test_timing_edit_reuses_original_take_but_requires_current_assembly(self):
        import hashlib
        import wave
        d=self.new();data=self.script(d)
        ff=os.environ.get('AI_MEDIA_TEST_FFMPEG') or shutil.which('ffmpeg')
        self.env['PATH']=str(Path(ff).parent)+os.pathsep+self.env.get('PATH','')
        raw=self.base/'take.wav'
        p=subprocess.run([ff,'-v','error','-y','-f','lavfi','-i',
            'sine=frequency=300:duration=4.5:sample_rate=48000','-c:a','pcm_s16le',str(raw)],
            capture_output=True,text=True,timeout=25)
        self.assertEqual(p.returncode,0,p.stderr)
        original_sha=hashlib.sha256(raw.read_bytes()).hexdigest()
        self.assertEqual(self.plan(d).returncode,0)
        old_plan=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        p=self.call('voiceover','--id',d.name,'--takes',raw)
        self.assertEqual(p.returncode,0,p.stderr)
        data['duration_seconds']=data['shots'][0]['seconds']=6
        data['shots'][0]['visual']='放大实际结果，口播内容保持原样'
        self.write(d/'99-专业工程/script.json',data)
        p=self.call('voiceover','--id',d.name,'--takes',raw,'--replace')
        self.assertEqual(p.returncode,2)
        self.assertIn('过期',p.stderr)
        p=self.plan(d)
        self.assertEqual(p.returncode,2)
        self.assertIn('原始 take 可复用',p.stderr)
        self.assertEqual(self.plan(d,'--replace').returncode,0)
        current=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        self.assertEqual(current['takes'][0]['text_sha256'],old_plan['takes'][0]['text_sha256'])
        p=self.call('voiceover','--id',d.name,'--takes',raw,'--replace')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(hashlib.sha256(raw.read_bytes()).hexdigest(),original_sha)
        report=json.loads((d/'99-专业工程/work/voiceover-check.json').read_text('utf8'))
        self.assertEqual(report['script_sha256'],hashlib.sha256((d/'99-专业工程/script.json').read_bytes()).hexdigest())
        self.assertEqual(report['speech_plan_sha256'],hashlib.sha256((d/'99-专业工程/work/speech-plan.json').read_bytes()).hexdigest())
        with wave.open(str(d/'02-媒体素材/配音/完整旁白.wav'),'rb') as f:
            self.assertAlmostEqual(f.getnframes()/f.getframerate(),6,places=3)

    def test_new_work_requires_speech_preflight_before_tts_assembly(self):
        d=self.new(); self.script(d)
        p=self.call('voiceover','--id',d.name,'--takes',self.base/'not-needed.wav')
        self.assertEqual(p.returncode,2)
        self.assertIn('speech-plan',p.stderr)

    def test_plan_tampering_and_script_revision_cannot_bypass_preflight(self):
        d=self.new(); self.script(d,'不用重复配置，就能制作视频。')
        self.assertEqual(self.plan(d).returncode,2)
        path=d/'99-专业工程/work/speech-plan.json';report=json.loads(path.read_text('utf8'))
        report['result']='READY';report['findings']=[];self.write(path,report)
        p=self.call('voiceover','--id',d.name,'--takes',self.base/'bad.wav')
        self.assertEqual(p.returncode,2);self.assertIn('发音',p.stderr)
        self.script(d);self.assertEqual(self.plan(d,'--replace').returncode,0)
        self.script(d,'给出内容主题，然后开始制作视频。')
        p=self.call('voiceover','--id',d.name,'--takes',self.base/'bad.wav')
        self.assertEqual(p.returncode,2);self.assertIn('过期',p.stderr)

    def test_known_word_scan_does_not_replace_every_zhong_character(self):
        d=self.new(); self.script(d,'重要的是内容质量，而不是产品重量。')
        p=self.plan(d);self.assertEqual(p.returncode,0,p.stderr)
        plan=json.loads((d/'99-专业工程/work/speech-plan.json').read_text('utf8'))
        self.assertEqual(plan['takes'][0]['text'],'重要的是内容质量，而不是产品重量。')
        self.assertEqual(plan['findings'],[])
        self.assertFalse(plan['pronunciation_verified'])
        self.assertTrue((self.root/'config/pronunciation.json').is_file())
        self.assertIsNotNone(json.loads((d/'99-专业工程/content.json').read_text('utf8'))['skill_version'])

    def test_editorial_focus_required_without_hardcoding_product_name(self):
        d=self.new(); data=self.script(d);data.pop('editorial_intent');self.write(d/'99-专业工程/script.json',data)
        self.assertEqual(self.call('check','--id',d.name).returncode,2)
        data['editorial_intent']={'audience':'消费者','primary_value':'快速煮咖啡',
            'secondary_values':['外观'],'evidence_plan':['实际冲煮演示']}
        self.write(d/'99-专业工程/script.json',data)
        self.assertEqual(self.call('check','--id',d.name).returncode,0)

    @unittest.skipUnless(os.environ.get('AI_MEDIA_TEST_FFMPEG') and os.environ.get('AI_MEDIA_TEST_FFPROBE'), 'explicit FFmpeg test binaries needed')
    def test_real_new_pipeline_preserves_origin_and_does_not_accept_asr_as_listening(self):
        import hashlib
        d=self.new();self.script(d)
        ff=os.environ['AI_MEDIA_TEST_FFMPEG']
        self.env['PATH']=str(Path(ff).parent)+os.pathsep+self.env.get('PATH','')
        self.assertEqual(self.plan(d).returncode,0)
        hashes=json.loads(self.call('hash','--id',d.name).stdout)
        review={**hashes,'result':'PASS','checks':[{'rule':'内容','result':'PASS'}],
            'facts_to_verify':[],'issues':[]}
        self.write(d/'99-专业工程/review.json',review)
        self.assertIn('核心价值',json.loads(self.call('check','--id',d.name).stdout)['script_ready'])
        review['focus_alignment']={'result':'PASS','reason':'实际视频生产流程为主线，环境复用仅为补充。'}
        self.write(d/'99-专业工程/review.json',review)
        raw=self.base/'take.wav';clip=self.base/'clip.mp4'
        for args in [ ['-f','lavfi','-i','sine=frequency=300:duration=4.5:sample_rate=22050','-c:a','pcm_s16le',str(raw)],
                      ['-f','lavfi','-i','color=c=black:s=160x288:r=24:d=5','-c:v','libx264','-pix_fmt','yuv420p',str(clip)] ]:
            p=subprocess.run([ff,'-v','error','-y',*args],capture_output=True,text=True,timeout=25)
            self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('voiceover','--id',d.name,'--takes',raw)
        self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('render','--id',d.name,'--materials',clip,'--audio',d/'02-媒体素材/配音/完整旁白.wav',
                    '--rights-confirmed','--width','160','--height','288')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertTrue((d/"视频封面.png").stat().st_size>200)
        meta=json.loads((d/'99-专业工程/video/render.json').read_text('utf8'))
        self.assertEqual(meta['provenance']['agent_id'],'workbuddy')
        vreview={**hashes,'video_sha256':meta['video_sha256'],'result':'PASS',
            'checks':[{'rule':'测试夹具','result':'PASS'}],'facts_to_verify':[],'issues':[],
            'pronunciation_check':{'result':'PASS','method':'ASR_only'}}
        self.write(d/'99-专业工程/video/review.json',vreview)
        p=self.call('package','--id',d.name,'--platform','douyin')
        self.assertEqual(p.returncode,2);self.assertIn('试听',p.stderr)
        vreview['pronunciation_check']={'result':'PASS','method':'actual_audio_review',
            'speech_plan_sha256':hashlib.sha256((d/'99-专业工程/work/speech-plan.json').read_bytes()).hexdigest(),
            'evidence':[{'start':0,'end':5,'note':'仅合成测试夹具验证记录协议，不作为语音自然度证明。'}]}
        self.write(d/'99-专业工程/video/review.json',vreview)
        p=self.call('package','--id',d.name,'--platform','douyin')
        self.assertEqual(p.returncode,0,p.stderr)
        pack=json.loads((d/'99-专业工程/platforms/douyin/package.json').read_text('utf8'))
        self.assertEqual(pack['provenance']['agent_id'],'workbuddy')
        self.assertEqual(pack['suggested_video_filename'],d.name+'.mp4')
        self.assertEqual(json.loads((d/'99-专业工程/publish-ledger.json').read_text('utf8'))['platforms']['douyin']['state'],'not_submitted')


if __name__ == '__main__':
    unittest.main()
