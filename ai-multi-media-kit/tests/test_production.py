"""Practical integration tests: no LLM, no external network, no real publishing."""
from __future__ import annotations
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def pyth(script,*args,input=None,timeout=70):
    return subprocess.run([sys.executable,str(ROOT/'scripts'/script),*map(str,args)],
        capture_output=True,encoding='utf-8',errors='replace',input=input,timeout=timeout)


def jsonwrite(path,content):
    path.write_text(json.dumps(content,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


class StudioProductionTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base=Path(tmp.name)
        self.root=base/'install';self.k=base/'knowledge'
        p=pyth('init_workspace.py','--install-root',self.root,'--knowledge-root',self.k)
        self.assertEqual(p.returncode,0,p.stderr)
        self.id='demo-001'
        p=self.call('new','--id',self.id,'--title','小团队如何做高质量内容')
        self.assertEqual(p.returncode,0,p.stderr)
        self.d=self.root/'outputs'/self.id
        self.write_review()

    def call(self,*args,input=None,timeout=90):
        return pyth('studio.py','--root',self.root,*args,input=input,timeout=timeout)

    def write_review(self):
        platforms=('xiaohongshu','douyin','tencent','bilibili','kuaishou','wechat_oa','zhihu')
        content={'content_id':self.id,'title':'小团队的内容增长实践','duration_seconds':6,
          'narration':'先确定品牌定位，再规划选题，明确真人审核，最终形成高质量的内容生产流程。',
          'shots':[{'seconds':3,'visual':'团队办公','voiceover':'先确定品牌定位'},
                   {'seconds':3,'visual':'电脑操作','voiceover':'再规划选题'}],
          'platforms':{x:{'title':f'{x}：小团队内容增长','description':'如何让真实内容生产更好','tags':['内容','AI']} for x in platforms},
          'article_markdown':'# 小团队内容生产\n\n真实原创内容。'}
        jsonwrite(self.d/'script.json',content)
        j=self.call('hash','--id',self.id)
        self.assertEqual(j.returncode,0,j.stderr)
        hashed=json.loads(j.stdout)
        review={'result':'PASS','score':95,'checks':[{'rule':'真实资料','result':'PASS','reason':'原创实验'}],
                'facts_to_verify':[],'issues':[], **hashed}
        jsonwrite(self.d/'review.json',review)

    def test_new_no_overwrite(self):
        d=self.d/'brief.md';d.write_text('手工备注',encoding='utf-8')
        resp=self.call('new','--id',self.id,'--title','试图覆盖')
        self.assertEqual(resp.returncode,2);self.assertEqual(d.read_text(encoding='utf-8'),'手工备注')

    def test_approval_requires_human_confirm_and_current_revision(self):
        p=self.call('approve','--stage','script','--id',self.id,'--who','我',input='WRONG\n')
        self.assertEqual(p.returncode,2)
        self.assertFalse((self.d/'approvals/script.json').exists())
        p=self.call('approve','--stage','script','--id',self.id,'--who','我',input=f'APPROVE:{self.id}:script\n')
        self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('check','--id',self.id)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(json.loads(p.stdout)['script_approval'],'valid')
        self.k.joinpath('review-rules.md').write_text('新增更严格的规则',encoding='utf-8')
        p=self.call('check','--id',self.id)
        self.assertIn('审核标准',json.loads(p.stdout)['script_approval'])

    def test_bad_claims_block_approval(self):
        r=json.loads((self.d/'review.json').read_text(encoding='utf-8'))
        r['facts_to_verify']=['尚未核实']
        jsonwrite(self.d/'review.json',r)
        p=self.call('approve','--stage','script','--id',self.id,'--who','我',input=f'APPROVE:{self.id}:script\n')
        self.assertEqual(p.returncode,2)
        self.assertIn('待核',p.stderr)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'FFmpeg not present')
    def test_real_video_and_7_packages(self):
        p=self.call('render','--id',self.id,'--materials','/missing.mp4','--rights-confirmed')
        self.assertEqual(p.returncode,2)
        p=self.call('approve','--stage','script','--id',self.id,'--who','Tester',input=f'APPROVE:{self.id}:script\n')
        self.assertEqual(p.returncode,0,p.stderr)
        clips=[]
        for i,col in enumerate(('blue','red')):
            dest=self.root/f'test{i}.mp4'
            resp=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',
                '-f','lavfi','-i',f'color=c={col}:s=160x280:r=15:d=1.5',
                '-c:v','libx264','-pix_fmt','yuv420p',dest],capture_output=True,timeout=30)
            self.assertEqual(resp.returncode,0,resp.stderr.decode(errors='replace'))
            clips.append(str(dest))
        asset_ids=[]
        for clip in clips:
            added=pyth('materials.py','--root',self.root,'add-file','--path',clip,
                       '--rights','owned','--license-note','test-generated original clip')
            self.assertEqual(added.returncode,0,added.stderr)
            asset_ids.append(json.loads(added.stdout)['id'])
        srt=self.root/'demo.srt';srt.write_text('1\n00:00:00,000 --> 00:00:01,000\n中文字幕\n\n',encoding='utf-8')
        p=self.call('render','--id',self.id,'--engine','ffmpeg','--material-ids',*asset_ids,
            '--subtitles',srt,'--rights-confirmed','--width','180','--height','320',timeout=150)
        self.assertEqual(p.returncode,0,p.stderr)
        v=self.d/'video/master.mp4';self.assertTrue(v.exists())
        used=json.loads((self.d/'video/materials-used.json').read_text(encoding='utf-8'))
        self.assertEqual([x['id'] for x in used['assets']],asset_ids)
        q=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type,width,height',
                         '-of','json',v],capture_output=True,text=True,timeout=20)
        self.assertEqual(q.returncode,0,q.stderr)
        streams=json.loads(q.stdout)['streams']
        self.assertEqual({s['codec_type'] for s in streams},{'video','audio'})
        p=self.call('package','--id',self.id)
        self.assertEqual(p.returncode,2)
        p=self.call('approve','--stage','video','--id',self.id,'--who','Tester',input=f'APPROVE:{self.id}:video\n')
        self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('package','--id',self.id)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(len(list((self.d/'platforms').glob('*/package.json'))),7)
        self.assertEqual(json.loads((self.d/'publish-ledger.json').read_text(encoding='utf-8'))['platforms']['douyin']['state'],'not_submitted')
        p=self.call('publish','--id',self.id,'--platform','douyin','--account','main','--execute')
        self.assertEqual(p.returncode,2) # No publish approval
        p=self.call('approve','--id',self.id,'--stage','publish','--platform','douyin',
             '--account','main','--who','Tester',input=f'APPROVE:{self.id}:publish:douyin\n')
        self.assertEqual(p.returncode,0,p.stderr)
        p=self.call('publish','--id',self.id,'--platform','douyin','--account','main','--execute')
        self.assertEqual(p.returncode,2) # No real CLI installed
        self.assertEqual(json.loads((self.d/'publish-ledger.json').read_text(encoding='utf-8'))['platforms']['douyin']['state'],'not_submitted')


    def test_chat_script_approval_records_user_statement_and_binds_revision(self):
        message=f'我已审核并批准 {self.id} 的脚本，可以进入视频制作。'
        result=self.call('approve','--id',self.id,'--stage','script','--who','本人',
                         '--chat-message',message,'--chat-ref','workbuddy:conversation-123:message-4')
        self.assertEqual(result.returncode,0,result.stderr)
        record=json.loads((self.d/'approvals'/'script.json').read_text(encoding='utf-8'))
        self.assertEqual(record['approval_method'],'conversation')
        self.assertEqual(record['chat_message'],message)
        self.assertEqual(record['chat_ref'],'workbuddy:conversation-123:message-4')
        self.assertEqual(record['script_sha256'],json.loads(self.call('hash','--id',self.id).stdout)['script_sha256'])
        checked=json.loads(self.call('check','--id',self.id).stdout)
        self.assertEqual(checked['script_approval'],'valid')
        script=self.d/'script.json'
        data=json.loads(script.read_text(encoding='utf-8'))
        data['narration']+='这是一项新修改。'
        jsonwrite(script,data)
        checked=json.loads(self.call('check','--id',self.id).stdout)
        self.assertIn('脚本内容发生变化',checked['script_approval'])

    def test_chat_requires_explicit_user_approval_for_exact_target(self):
        messages=['可以','我在这里直接批准你可以吗？',
                  '我批准 demo-002 的脚本。','我批准 demo-001 的成片。',
                  '我不批准 demo-001 的脚本。','我批准 demo-001 的脚本，先不要做视频。',
                  '我批准 demo-001 的脚本吗？',
                  '请优化脚本审批支持对话确认']
        for message in messages:
            with self.subTest(message=message):
                p=self.call('approve','--id',self.id,'--stage','script','--who','本人',
                            '--chat-message',message)
                self.assertEqual(p.returncode,2,p.stderr)
                self.assertFalse((self.d/'approvals'/'script.json').exists())
        # A reference is not itself user approval, and must never trigger terminal input implicitly.
        p=self.call('approve','--id',self.id,'--stage','script','--who','本人',
                    '--chat-ref','chat:message-8',input='')
        self.assertEqual(p.returncode,2,p.stderr)
        self.assertFalse((self.d/'approvals'/'script.json').exists())

    def test_chat_video_and_publish_check_separate_stage_account_and_assets(self):
        p=self.call('approve','--id',self.id,'--stage','video','--who','本人',
                    '--chat-message',f'我已验收并批准 {self.id} 的成片。')
        self.assertEqual(p.returncode,2)
        self.assertFalse((self.d/'approvals'/'video.json').exists())
        p=self.call('approve','--id',self.id,'--stage','script','--who','本人',
                    '--chat-message',f'我批准 {self.id} 的脚本。')
        self.assertEqual(p.returncode,0,p.stderr)
        video=self.d/'video'/'master.mp4';video.parent.mkdir(parents=True)
        video.write_bytes(b'synthetic test bytes; not a real video')
        bad=self.call('approve','--id',self.id,'--stage','video','--who','本人',
                      '--chat-message',f'我批准 {self.id} 的脚本。')
        self.assertEqual(bad.returncode,2)
        p=self.call('approve','--id',self.id,'--stage','video','--who','本人',
                    '--chat-message',f'我已验收并批准 {self.id} 的成片。')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(self.call('package','--id',self.id).returncode,0)
        msg=f'我批准 {self.id} 发布到 douyin，账号 main。'
        wrong=self.call('approve','--id',self.id,'--stage','publish','--platform','douyin',
                        '--account','other','--who','本人','--chat-message',msg)
        self.assertEqual(wrong.returncode,2)
        self.assertFalse((self.d/'approvals'/'publish-douyin.json').exists())
        ok=self.call('approve','--id',self.id,'--stage','publish','--platform','douyin',
                     '--account','main','--who','本人','--chat-message',msg)
        self.assertEqual(ok.returncode,0,ok.stderr)
        record=json.loads((self.d/'approvals'/'publish-douyin.json').read_text(encoding='utf-8'))
        self.assertEqual(record['account'],'main')
        self.assertEqual(record['approval_method'],'conversation')
        # Conversation-stage approval never authorizes or performs the actual upload.
        self.assertEqual(json.loads((self.d/'publish-ledger.json').read_text(encoding='utf-8'))['platforms']['douyin']['state'],'not_submitted')

    def test_installer_plan_does_not_download(self):
        p=pyth('installer.py','--root',self.root,'--profile','core')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('PLAN_ONLY',p.stdout)
        self.assertFalse((self.root/'tools/marketingskills').exists())


if __name__=='__main__':unittest.main()
