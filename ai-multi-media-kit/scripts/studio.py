#!/usr/bin/env python3
"""AI Media Studio: deterministic content state machine and local publishing guardrails.

The AI work (ideas, script writing, qualitative review) belongs to Codex following
.agents/skills instructions. This CLI validates and persists state; it never calls
an LLM or an external publishing API without explicit user action.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

PLATFORMS = ('xiaohongshu', 'douyin', 'tencent', 'bilibili', 'kuaishou', 'wechat_oa', 'zhihu')
VIDEO_PLATFORMS = PLATFORMS[:5]
ID_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')


def fail(reason: str):
    raise ValueError(reason)


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def filehash(file: Path) -> str:
    return digest(file.read_bytes())


def load(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def save(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(tmp, path)


def workspace(root: str):
    p = Path(root).expanduser().resolve()
    cfg = p / 'config' / 'workspace.json'
    if not cfg.is_file():
        fail('工作区未初始化：先运行 SETUP-WINDOWS.cmd 或 scripts/init_workspace.py')
    d = load(cfg)
    if Path(d['install_root']).resolve() != p:
        fail('配置路径已被移动：请用迁移工具或重新建立工作区，不要直接修改根目录')
    knowledge = Path(d['knowledge_root']).resolve()
    if not knowledge.is_dir():
        fail(f'知识库不可访问：{knowledge}')
    return p, knowledge


def content_dir(root: Path, content_id: str):
    if not ID_RE.fullmatch(content_id):
        fail('内容 ID 仅允许字母、数字、下划线和连字符（最长64位）')
    return root / 'outputs' / content_id


def paths(root: Path, content_id: str):
    d = content_dir(root, content_id)
    if not (d / 'content.json').is_file():
        fail(f'内容不存在：{content_id}；先执行 new')
    return d


def ensure_approved_script(d: Path, knowledge: Path):
    j = d / 'script.json'
    r = d / 'review.json'
    a = d / 'approvals' / 'script.json'
    if not all(p.is_file() for p in (j, r, a)):
        fail('缺少脚本、AI审核或人工脚本批准记录')
    script = load(j)
    review = load(r)
    approval = load(a)
    digest_script = filehash(j)
    if review.get('result') != 'PASS' or not (isinstance(review.get('checks'), list) and len(review['checks']) > 0):
        fail('审核不是 PASS 或缺少审核明细')
    if review.get('script_sha256') != digest_script:
        fail('脚本内容发生变化，需要重新 AI 审核')
    if review.get('review_standard_sha256') != filehash(knowledge / 'review-rules.md'):
        fail('企业审核标准已经更新，需要重新 AI 审核')
    if review.get('facts_to_verify') or any(x.get('result') != 'PASS' for x in review['checks']):
        fail('审核存在未解决的事实或检查项')
    if (approval.get('script_sha256') != digest_script or
            approval.get('review_sha256') != filehash(r)):
        fail('人工批准对应的脚本/审核已过期，请重新批准')
    return script


def video_path(d):
    return d / 'video' / 'master.mp4'


def ensure_video_approved(d: Path, knowledge: Path):
    script = ensure_approved_script(d, knowledge)
    v = video_path(d)
    a = d / 'approvals' / 'video.json'
    if not v.is_file() or not a.is_file():
        fail('缺少成片或人工验片批准')
    obj = load(a)
    if obj.get('video_sha256') != filehash(v) or obj.get('script_sha256') != filehash(d/'script.json'):
        fail('成片或脚本更新后，人工视频审批失效')
    return script


def cmd_new(a):
    root, knowledge = workspace(a.root)
    d = content_dir(root, a.id)
    if d.exists():
        fail(f'内容 ID 已存在，不允许覆盖：{a.id}')
    d.mkdir(parents=True)
    data = {'schema': 2, 'content_id': a.id, 'title': a.title, 'created_at_utc': now(),
            'knowledge_root': str(knowledge), 'platforms': list(PLATFORMS)}
    save(d/'content.json', data)
    (d/'brief.md').write_text('# '+a.title+'\n\n目标用户：\n\n证据与参考：\n\n创作角度：\n', encoding='utf-8')
    save(d/'script.template.json', {'content_id': a.id, 'title': a.title, 'duration_seconds': 30,
          'narration': '请由 Codex 完成真实口播稿', 'shots': [{'seconds': 10, 'visual': '实拍镜头', 'voiceover': '示例'}],
          'platforms': {p: {'title': '', 'description': '', 'tags': []} for p in PLATFORMS},
          'article_markdown': '公众号/知乎衍生图文（如适用）'})
    save(d/'review.template.json', {'result': 'REVISE', 'score': 0,
         'script_sha256': '运行 studio hash 获得', 'review_standard_sha256': filehash(knowledge/'review-rules.md'),
         'checks': [{'rule': '企业审核标准第1条', 'result': 'REVISE', 'reason': '未审核'}],
         'facts_to_verify': ['尚待人工查证'], 'issues': ['请先填写真实审核意见']})
    save(d/'publish-ledger.json', {'platforms': {p: {'state': 'not_submitted'} for p in PLATFORMS}})
    print(f'CREATED {d}\n下一步：Codex 读取知识库完成 brief.md / script.json / review.json，运行 hash/check')


def cmd_hash(a):
    root, knowledge = workspace(a.root)
    d = paths(root, a.id)
    sj = d/'script.json'
    if not sj.is_file():
        fail('请先由 Codex 创建 script.json')
    print(json.dumps({'script_sha256':filehash(sj),
          'review_standard_sha256':filehash(knowledge/'review-rules.md')}, ensure_ascii=False, indent=2))


def check_script(root, knowledge, d):
    script_path = d/'script.json'
    if not script_path.is_file():
        fail('缺少 script.json（不是 script.template.json），请由 Codex 生成')
    j=load(script_path)
    if j.get('content_id') != d.name: fail('script.json 的 content_id 与目录不一致')
    for field in ('title','narration'):
        if not isinstance(j.get(field),str) or len(j[field].strip())<5: fail(f'script.{field} 必须是有效文本')
    shots=j.get('shots')
    if not isinstance(shots,list) or not shots: fail('script.shots 至少一个分镜')
    for shot in shots:
        if not isinstance(shot,dict) or not isinstance(shot.get('visual'),str) or not shot['visual'].strip():
            fail('每个分镜需要 visual 描述')
    if not isinstance(j.get('platforms'),dict): fail('platforms 必须是对象')
    for p in PLATFORMS:
        item=j['platforms'].get(p)
        if not isinstance(item,dict) or not item.get('title') or not isinstance(item.get('tags'),list):
            fail(f'平台 {p} 缺少 title 或 tags')
    return j


def cmd_check(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    j=check_script(root,k,d)
    result={'script_structure':'valid','script_sha256':filehash(d/'script.json')}
    try:
        ensure_approved_script(d,k)
        result['script_approval']='valid'
    except ValueError as e:
        result['script_approval']='not_ready: '+str(e)
    try:
        ensure_video_approved(d,k)
        result['video_approval']='valid'
    except ValueError as e:
        result['video_approval']='not_ready: '+str(e)
    print(json.dumps(result,ensure_ascii=False,indent=2))


def approve_prompt(expected):
    print('确认将写入不可自动撤销的人工审批记录，Codex 不得代替真实用户确认。')
    typed=input(f'请由本人输入 {expected} ：').strip()
    if typed!=expected: fail('审批确认文本不匹配，已取消')


def cmd_approve(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    if not a.who.strip(): fail('--who 不能为空')
    if a.stage=='script':
        script=check_script(root,k,d)
        r=d/'review.json'
        if not r.exists(): fail('review.json 尚未生成')
        review=load(r)
        if review.get('result')!='PASS' or not review.get('checks') or any(c.get('result')!='PASS' for c in review['checks']):
            fail('审核不是全项 PASS')
        if review.get('facts_to_verify'): fail('存在待核事实，不能审批')
        if review.get('script_sha256')!=filehash(d/'script.json') or review.get('review_standard_sha256')!=filehash(k/'review-rules.md'):
            fail('审核 hash 不匹配，请 Codex 重新审核')
        stage_data={'script_sha256': filehash(d/'script.json'), 'review_sha256':filehash(r)}
    elif a.stage=='video':
        ensure_approved_script(d,k)
        v=video_path(d)
        if not v.is_file() or v.stat().st_size==0: fail('没有实际成片')
        stage_data={'script_sha256':filehash(d/'script.json'), 'video_sha256':filehash(v)}
    elif a.stage=='publish':
        if not a.platform or a.platform not in PLATFORMS: fail('发布审批要求指定 --platform')
        if not a.account: fail('发布审批要求指定 --account（账号别名，不是凭据）')
        if a.platform in VIDEO_PLATFORMS: ensure_video_approved(d,k)
        else: ensure_approved_script(d,k)
        package=d/'platforms'/a.platform/'package.json'
        if not package.is_file(): fail('先执行 package 生成平台待发包')
        stage_data={'platform':a.platform,'account':a.account, 'package_sha256':filehash(package),
          'script_sha256':filehash(d/'script.json')}
        if a.platform in VIDEO_PLATFORMS: stage_data['video_sha256']=filehash(video_path(d))
    else: fail('不支持的审批阶段')
    expected=f'APPROVE:{a.id}:{a.stage}' + (f':{a.platform}' if a.stage=='publish' else '')
    approve_prompt(expected)
    stage_data.update({'human':a.who,'approved_at_utc':now(),'stage':a.stage, 'content_id':a.id})
    rel=f'publish-{a.platform}' if a.stage=='publish' else a.stage
    save(d/'approvals'/f'{rel}.json',stage_data)
    print('APPROVED (human checkpoint):',d/'approvals'/f'{rel}.json')


def load_ffmpeg_bin(root, base):
    p=root/'tools'/'ffmpeg'/'bin'/(base+'.exe' if os.name=='nt' else base)
    return str(p) if p.is_file() else shutil.which(base)


def run(cmd, cwd=None, timeout=240):
    proc=subprocess.run([str(v) for v in cmd],cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,
                        encoding='utf-8',errors='replace',timeout=timeout)
    if proc.returncode:
        raise RuntimeError(f'工具执行失败（退出码 {proc.returncode}）：{str(cmd[0])}\n{proc.stderr[-1400:]}')
    return proc.stdout


def render_ffmpeg(root, d, clips, audio, subtitles, width, height):
    ffmpeg=load_ffmpeg_bin(root,'ffmpeg'); ffprobe=load_ffmpeg_bin(root,'ffprobe')
    if not ffmpeg or not ffprobe: fail('缺少 ffmpeg / ffprobe，先运行 doctor 或指定本地 FFmpeg')
    if not clips: fail('至少传入一段本地视频素材 --materials')
    for clip in clips:
        if not clip.is_file(): fail('素材不存在：'+str(clip))
    if audio and not audio.is_file(): fail('音频不存在')
    if subtitles and not subtitles.is_file(): fail('字幕不存在')
    out=video_path(d)
    out.parent.mkdir(exist_ok=True,parents=True)
    if out.exists() and not getattr(render_ffmpeg,'allow_replace',False): fail('成片已存在。修改后请显式加 --replace（将导致审批失效）')
    with tempfile.TemporaryDirectory(prefix='ai-media-') as td:
        tmp=Path(td)
        pieces=[]
        for i,src in enumerate(clips):
            dst=tmp/f'part-{i:03d}.mp4'
            vf=f'scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24'
            run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',src,'-map','0:v:0',
                '-vf',vf,'-an','-c:v','libx264','-preset','veryfast','-crf','24','-pix_fmt','yuv420p',dst],timeout=300)
            pieces.append(dst)
        concat=tmp/'concat.txt'
        concat.write_text(''.join("file '"+str(p.as_posix()).replace("'","'\\''")+"'\n" for p in pieces),encoding='utf-8')
        merged=tmp/'merged.mp4'
        run([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',concat,
             '-c','copy',merged],timeout=240)
        probe=json.loads(run([ffprobe,'-v','error','-show_format','-of','json',merged]))
        duration=float(probe['format']['duration'])
        if duration<=0: fail('视频时长无效')
        cmd=[ffmpeg,'-hide_banner','-loglevel','error','-y','-i',merged]
        if audio: cmd.extend(['-i',audio])
        else: cmd.extend(['-f','lavfi','-i','anullsrc=channel_layout=stereo:sample_rate=48000'])
        if subtitles:
            sub=tmp/'captions.srt'
            shutil.copy2(subtitles,sub)
            # Use temp cwd and relative filename to avoid colon/backslash escaping on Windows.
            cmd.extend(['-vf',"subtitles=captions.srt:force_style='FontSize=18,Outline=2,MarginV=60'"])
        cmd.extend(['-map','0:v:0','-map','1:a:0','-t',f'{duration:.3f}', '-c:v','libx264',
                    '-preset','veryfast','-crf','23','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k',
                    '-movflags','+faststart',out])
        run(cmd,cwd=tmp,timeout=360)
    result=json.loads(run([ffprobe,'-v','error','-show_streams','-show_format','-of','json',out]))
    streams=result.get('streams',[])
    vids=[s for s in streams if s.get('codec_type')=='video']
    aud=[s for s in streams if s.get('codec_type')=='audio']
    if not vids or not aud or vids[0].get('width')!=width or vids[0].get('height')!=height:
        fail('实际视频校验失败：音视频轨道或尺寸有误')
    save(d/'video'/'render.json',{'engine':'ffmpeg','video_sha256':filehash(out),'created_at_utc':now(),
         'clips':[str(x) for x in clips],'audio':str(audio) if audio else None,
         'subtitles':str(subtitles) if subtitles else None,'duration_seconds':float(result['format']['duration'])})
    return out


def cmd_render(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    script=ensure_approved_script(d,k)
    files=[Path(x).expanduser().resolve() for x in (a.materials or [])]
    if not files: fail('请用 --materials 指定一个或多个本地视频文件')
    # Do not use materials without provenance info, unless user consciously supplies right-to-use.
    if not a.rights_confirmed: fail('必须传入 --rights-confirmed 表示已核对素材来源/授权（不代表工具自动校验版权）')
    if a.engine=='ffmpeg':
        render_ffmpeg.allow_replace=a.replace
        result=render_ffmpeg(root,d,files,Path(a.audio).expanduser().resolve() if a.audio else None,
            Path(a.subtitles).expanduser().resolve() if a.subtitles else None, a.width,a.height)
        print('RENDERED:',result,'\n备注：未提供 audio 时为静音视频。FFmpeg 不会自动生成 TTS。')
    else:
        mpt=root/'tools'/'MoneyPrinterTurbo'
        py=mpt/'.venv'/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
        if not py.is_file() or not (mpt/'cli.py').is_file():
            fail('MoneyPrinterTurbo 尚未安装/完成 uv sync。运行 installer --component mpt')
        narration=script['narration']
        if len(narration)>5000: fail('口播稿过长，建议拆分任务以防 CLI 参数限制')
        # CLI emits results into its own task storage; do not falsely assume output location.
        args=[py,'cli.py','--video-script',narration,'--video-source','local',
              '--video-materials',','.join(map(str,files)),'--video-aspect','9:16','--stop-at','video']
        if a.audio: args.extend(['--custom-audio-file',str(Path(a.audio).resolve())])
        if a.no_voice: args.extend(['--voice-name','no-voice'])
        if a.dry_run:
            print('DRY_RUN (MPT):',json.dumps(list(map(str,args)),ensure_ascii=False))
            return
        if video_path(d).exists() and not a.replace: fail('现有成片不允许覆盖，需 --replace')
        print('即将启动 MPT。首次使用需本地登录/安装/配置；不保证所有 TTS 或服务无费用。')
        r=subprocess.run([str(x) for x in args],cwd=mpt,env=tool_env(root))
        if r.returncode: fail(f'MPT 返回退出码 {r.returncode}，未更新 master.mp4')
        print('MPT 任务已执行。请找到 MPT 实际生成的 MP4，用 import-video 导入受控成果目录后再验片。')


def cmd_import_video(a):
    root,k=workspace(a.root); d=paths(root,a.id); ensure_approved_script(d,k)
    src=Path(a.file).expanduser().resolve()
    if not src.is_file() or src.suffix.lower()!='.mp4': fail('只允许导入存在的 .mp4 视频文件')
    dst=video_path(d); dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists() and not a.replace: fail('已有成片，需要 --replace 明确覆盖')
    if src!=dst: shutil.copy2(src,dst)
    save(d/'video'/'render.json',{'engine':'import','source':str(src),'video_sha256':filehash(dst),'created_at_utc':now()})
    print('IMPORTED:',dst)


def cmd_package(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    script=check_script(root,k,d)
    targets=list(PLATFORMS) if a.platform=='all' else [a.platform]
    for p in targets:
        if p in VIDEO_PLATFORMS: ensure_video_approved(d,k)
        else: ensure_approved_script(d,k)
    for p in targets:
        if (d/'platforms'/p/'package.json').exists() and not a.replace:
            fail(f'{p} 发布包已存在，使用 --replace 才能覆盖；没有修改任何平台包')
        if p in ('wechat_oa', 'zhihu') and (d/'platforms'/p/'article.md').exists() and not a.replace:
            fail(f'{p} 文章已存在，需要 --replace')
    for p in targets:
        item=script['platforms'][p]
        article=script.get('article_markdown','') if p not in VIDEO_PLATFORMS else None
        pack={'schema':1,'content_id':a.id,'platform':p,'state':'prepared_not_published',
              'title':item['title'],'description':item.get('description',''), 'tags':item.get('tags',[]),
              'category_id': item.get('category_id'),
              'video_path':str(video_path(d)) if p in VIDEO_PLATFORMS else None,
              'article_path':None,'generated_at_utc':now(), 'account_alias':None}
        target=d/'platforms'/p
        target.mkdir(parents=True,exist_ok=True)
        if article is not None:
            doc=target/'article.md'
            if doc.exists() and not a.replace: fail(f'{p} 文章已存在，使用 --replace 才能覆盖')
            doc.write_text(article or '(请由 Codex 提供公众号/知乎适配图文)',encoding='utf-8')
            pack['article_path']=str(doc)
        # Content must not silently overwrite previous platform variant/approval.
        dest=target/'package.json'
        if dest.exists() and not a.replace: fail(f'{p} 发布包已存在，使用 --replace 才能覆盖')
        save(dest,pack)
        print('PREPARED:',dest)
    print('已生成待发布包，没有任何网络投稿行为。')


def sau_binary(root):
    return root/'tools'/'social-auto-upload'/'.venv'/('Scripts/sau.exe' if os.name=='nt' else 'bin/sau')


def tool_env(root):
    env=os.environ.copy()
    env['UV_CACHE_DIR']=str(root/'runtime'/'uv-cache')
    env['UV_PYTHON_INSTALL_DIR']=str(root/'runtime'/'uv-python')
    env['XDG_CACHE_HOME']=str(root/'runtime'/'cache')
    env['PLAYWRIGHT_BROWSERS_PATH']=str(root/'runtime'/'browsers')
    return env


def cmd_publish(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    if a.platform not in PLATFORMS: fail('未知平台')
    p=a.platform
    packfile=d/'platforms'/p/'package.json'
    approved=d/'approvals'/f'publish-{p}.json'
    if not packfile.is_file() or not approved.is_file(): fail('发布前需先生成发布包并人工审批')
    pack=load(packfile); auth=load(approved)
    if auth.get('package_sha256')!=filehash(packfile) or auth.get('account')!=a.account:
        fail('发布包/账号和人工审批记录不一致，拒绝发布')
    if p in VIDEO_PLATFORMS:
        ensure_video_approved(d,k)
        if auth.get('video_sha256')!=filehash(video_path(d)):
            fail('成片已更新，需要重新批准')
    else: ensure_approved_script(d,k)
    if p not in VIDEO_PLATFORMS:
        print(f'{p} 使用已安装的专项发布 Skill 人工预览发布，本 CLI 不模拟未经验证的接口。')
        print('文章路径：',pack.get('article_path'))
        return
    cli=sau_binary(root)
    if not cli.is_file(): fail('未安装 social-auto-upload，请先运行 installer --component social')
    # Bilibili normally needs a category ID (tid); never invent category assignment.
    tid=a.tid or pack.get('category_id')
    if p=='bilibili' and not tid:
        fail('B站发布缺少分区 TID：请在 script.json 平台配置提供 category_id，或命令加 --tid')
    cmd=[cli,p,'upload-video','--account',a.account,'--file',video_path(d),
          '--title',pack['title'],'--desc',pack.get('description','')]
    if p=='bilibili': cmd.extend(['--tid',str(tid)])
    if pack.get('tags'): cmd.extend(['--tags',','.join(str(t) for t in pack['tags'])])
    if not a.execute:
        print('DRY_RUN — 即将调用的命令：\n',subprocess.list2cmdline([str(x) for x in cmd]))
        print('没有投稿。若账号已登录并确认真实发布，使用 --execute。')
        return
    approve_prompt(f'PUBLISH:{a.id}:{p}')
    ledger_file=d/'publish-ledger.json'; ledger=load(ledger_file)
    prev=ledger['platforms'].get(p,{})
    if prev.get('state') in ('submitted_unknown','published'):
        fail('该平台已有未知/已发布状态：禁止重复盲发，先人工确认状态')
    ledger['platforms'][p]={'state':'attempting','account':a.account,'at':now()}
    save(ledger_file,ledger)
    try:
        proc=subprocess.run([str(x) for x in cmd],cwd=cli.parent.parent,env=tool_env(root),
                            capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900)
        # Never store third-party stdout/stderr: it might include cookie/token.
        # Some CLI versions exit 0 before the platform has fully accepted the post.
        ledger['platforms'][p]={'state':'submitted_unknown','account':a.account,'returncode':proc.returncode,
            'at':now(),'note':'请在平台后台核实；程序退出码不代表公开发布成功'}
        print('CLI returned',proc.returncode,'\n请到官方后台核查发布状态，使用 confirm-published 更新账本。')
    except (subprocess.TimeoutExpired, OSError) as exc:
        ledger['platforms'][p]={'state':'submitted_unknown','account':a.account,'at':now(),
            'note':'超时/异常，未知是否提交；禁止盲重试'}
        print('UPLOAD STATUS UNKNOWN:',type(exc).__name__)
    finally: save(ledger_file,ledger)


def cmd_confirm_published(a):
    root,_=workspace(a.root); d=paths(root,a.id)
    ledger_file=d/'publish-ledger.json'; ledger=load(ledger_file)
    prev=ledger['platforms'].get(a.platform,{})
    if prev.get('state')!='submitted_unknown': fail('仅允许确认已提交待核查状态')
    if not a.url.startswith('https://'): fail('必须提供平台后台可核对的 HTTPS 作品链接')
    approve_prompt(f'VERIFY:{a.id}:{a.platform}')
    ledger['platforms'][a.platform]={**prev,'state':'published','url':a.url,
                                     'verified_by':a.who,'verified_at_utc':now()}
    save(ledger_file,ledger)
    print('VERIFIED:',a.url)


def cmd_status(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    result={'content_id':a.id,'script_exists':(d/'script.json').is_file(),
            'review_exists':(d/'review.json').is_file(),'video_exists':video_path(d).is_file(),
            'prepared_platforms':[p for p in PLATFORMS if (d/'platforms'/p/'package.json').exists()],
            'publish':load(d/'publish-ledger.json')['platforms']}
    for key,fn in (('script_ready',ensure_approved_script),('video_ready',ensure_video_approved)):
        try:fn(d,k);result[key]=True
        except ValueError as e:result[key]=False;result[key+'_reason']=str(e)
    print(json.dumps(result,indent=2,ensure_ascii=False))


def parse():
    parser=argparse.ArgumentParser(description='AI Media Studio - 标准化内容和人工审批 CLI')
    parser.add_argument('--root',required=True,help='安装根目录（与 config/workspace.json 一致）')
    sub=parser.add_subparsers(dest='command',required=True)
    n=sub.add_parser('new');n.add_argument('--id',required=True);n.add_argument('--title',required=True);n.set_defaults(func=cmd_new)
    h=sub.add_parser('hash');h.add_argument('--id',required=True);h.set_defaults(func=cmd_hash)
    c=sub.add_parser('check');c.add_argument('--id',required=True);c.set_defaults(func=cmd_check)
    c=sub.add_parser('status');c.add_argument('--id',required=True);c.set_defaults(func=cmd_status)
    ap=sub.add_parser('approve');ap.add_argument('--id',required=True);ap.add_argument('--stage',required=True,choices=['script','video','publish']);ap.add_argument('--platform',choices=PLATFORMS);ap.add_argument('--account');ap.add_argument('--who',required=True);ap.set_defaults(func=cmd_approve)
    ren=sub.add_parser('render');ren.add_argument('--id',required=True);ren.add_argument('--engine',choices=['ffmpeg','mpt'],default='ffmpeg');
    ren.add_argument('--materials',nargs='+',required=True);ren.add_argument('--audio');ren.add_argument('--subtitles');ren.add_argument('--rights-confirmed',action='store_true');ren.add_argument('--no-voice',action='store_true');ren.add_argument('--width',type=int,default=720);ren.add_argument('--height',type=int,default=1280);ren.add_argument('--replace',action='store_true');ren.add_argument('--dry-run',action='store_true');ren.set_defaults(func=cmd_render)
    ip=sub.add_parser('import-video');ip.add_argument('--id',required=True);ip.add_argument('--file',required=True);ip.add_argument('--replace',action='store_true');ip.set_defaults(func=cmd_import_video)
    pkg=sub.add_parser('package');pkg.add_argument('--id',required=True);pkg.add_argument('--platform',choices=['all',*PLATFORMS],default='all');pkg.add_argument('--replace',action='store_true');pkg.set_defaults(func=cmd_package)
    pub=sub.add_parser('publish');pub.add_argument('--id',required=True);pub.add_argument('--platform',required=True,choices=PLATFORMS);pub.add_argument('--account',required=True);pub.add_argument('--tid',help='B站视频分区ID');pub.add_argument('--execute',action='store_true');pub.set_defaults(func=cmd_publish)
    verify=sub.add_parser('confirm-published');verify.add_argument('--id',required=True);verify.add_argument('--platform',required=True,choices=PLATFORMS);verify.add_argument('--url',required=True);verify.add_argument('--who',required=True);verify.set_defaults(func=cmd_confirm_published)
    return parser.parse_args()


def main():
    a=parse()
    try: a.func(a);return 0
    except (ValueError,FileNotFoundError,RuntimeError,json.JSONDecodeError,subprocess.TimeoutExpired) as e:
        print('ERROR:',str(e),file=sys.stderr);return 2


if __name__=='__main__': raise SystemExit(main())
