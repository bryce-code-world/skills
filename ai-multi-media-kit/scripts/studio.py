#!/usr/bin/env python3
"""AI Media Studio: deterministic content state machine and local publishing guardrails.

The AI work (ideas, script writing, qualitative review) belongs to 当前 AI Agent following
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
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workspace_paths import output_directory
from media_audio import inspect_video, mix_takes

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
    return output_directory(root, load(root / 'config' / 'workspace.json')) / content_id


def paths(root: Path, content_id: str):
    d = content_dir(root, content_id)
    if not (d / 'content.json').is_file():
        fail(f'内容不存在：{content_id}；先执行 new')
    return d


def ensure_reviewed_script(d: Path, knowledge: Path):
    j = d / 'script.json'
    r = d / 'review.json'
    if not j.is_file() or not r.is_file():
        fail('缺少脚本或 AI 审核结果，请自动生成并审核')
    script = check_script(d)
    review = load(r)
    if review.get('result') != 'PASS' or not review.get('checks') or any(
            not isinstance(c, dict) or c.get('result') != 'PASS' for c in review['checks']):
        fail('脚本 AI 审核未全部 PASS，请自动修改后重新审核')
    if review.get('facts_to_verify') or review.get('issues'):
        fail('脚本审核存在待核事实或未解决问题')
    if review.get('script_sha256') != filehash(j):
        fail('脚本内容发生变化，需要重新 AI 审核')
    if review.get('review_standard_sha256') != filehash(knowledge / 'review-rules.md'):
        fail('企业审核标准已经更新，需要重新 AI 审核')
    return script


def video_path(d):
    return d / 'video' / 'master.mp4'


def ensure_video_ready(d: Path, knowledge: Path, root: Path):
    script = ensure_reviewed_script(d, knowledge)
    v = video_path(d)
    meta_path = d / 'video' / 'render.json'
    review_path = d / 'video' / 'review.json'
    if not v.is_file() or not v.stat().st_size or not meta_path.is_file() or not review_path.is_file():
        fail('缺少成片、渲染记录或 AI 成片审核，请自动补齐')
    meta = load(meta_path)
    review = load(review_path)
    v_sha = filehash(v)
    s_sha = filehash(d / 'script.json')
    if meta.get('video_sha256') != v_sha or meta.get('script_sha256') != s_sha:
        fail('成片或脚本发生变化，需要重新渲染或导入')
    if review.get('result') != 'PASS' or not review.get('checks') or any(
            not isinstance(c, dict) or c.get('result') != 'PASS' for c in review['checks']):
        fail('成片 AI 审核未全部 PASS，请自动修复后重新审核')
    if review.get('issues') or review.get('facts_to_verify'):
        fail('成片 AI 审核存在未解决问题')
    if (review.get('video_sha256') != v_sha or review.get('script_sha256') != s_sha or
            review.get('review_standard_sha256') != filehash(knowledge / 'review-rules.md')):
        fail('成片或审核标准已变化，需要重新执行 AI 成片审核')
    # An AI-authored PASS is insufficient: inspect the *actual* encoded soundtrack.
    ffmpeg = load_ffmpeg_bin(root, 'ffmpeg')
    ffprobe = load_ffmpeg_bin(root, 'ffprobe')
    if not ffmpeg or not ffprobe:
        fail('技术音频验收需要已安装的 FFmpeg/ffprobe，不能仅靠 AI 自报 PASS')
    technical = inspect_video(ffmpeg, ffprobe, v, script['shots'])
    if technical['result'] != 'PASS':
        fail('成片技术音频验收失败：' + '; '.join(technical['issues']))
    return script


def publish_targets(values):
    targets = {}
    for raw in values or []:
        if raw.count(':') != 1:
            fail('发布范围格式须为 platform:account（账号别名）')
        platform, account = raw.split(':', 1)
        if platform not in PLATFORMS or not ID_RE.fullmatch(account):
            fail('发布范围需要明确支持的平台及有效账号别名，不支持通配符')
        if platform in targets:
            fail('同一平台只能绑定一个账号；不可重复或覆盖')
        targets[platform] = account
    return targets


def cmd_new(a):
    root, knowledge = workspace(a.root)
    d = content_dir(root, a.id)
    if d.exists():
        fail(f'内容 ID 已存在，不允许覆盖：{a.id}')
    targets = publish_targets(a.publish_target)
    if a.task_ref and (len(a.task_ref) > 256 or any(c in a.task_ref for c in '\r\n')):
        fail('任务来源引用不合法')
    d.mkdir(parents=True)
    data = {'schema': 3, 'content_id': a.id, 'title': a.title, 'created_at_utc': now(),
            'knowledge_root': str(knowledge), 'platforms': list(PLATFORMS),
            'publish_targets': targets, 'task_ref': a.task_ref or None}
    save(d/'content.json', data)
    (d/'brief.md').write_text('# '+a.title+'\n\n目标用户：\n\n证据与参考：\n\n创作角度：\n', encoding='utf-8')
    save(d/'script.template.json', {'content_id': a.id, 'title': a.title, 'duration_seconds': 30,
          'narration': '请由 当前 AI Agent 完成真实口播稿', 'shots': [{'seconds': 10, 'visual': '实拍镜头', 'voiceover': '示例'}],
          'platforms': {p: {'title': '', 'description': '', 'tags': []} for p in PLATFORMS},
          'article_markdown': '公众号/知乎衍生图文（如适用）'})
    save(d/'review.template.json', {'result': 'REVISE', 'score': 0,
         'script_sha256': '运行 studio hash 获得', 'review_standard_sha256': filehash(knowledge/'review-rules.md'),
         'checks': [{'rule': '企业审核标准第1条', 'result': 'REVISE', 'reason': '未审核'}],
         'facts_to_verify': ['待 AI 核查的事实'], 'issues': ['请先由 AI 根据真实证据完成审核']})
    save(d/'publish-ledger.json', {'platforms': {p: {'state': 'not_submitted'} for p in PLATFORMS}})
    print(f'CREATED {d}\n下一步：当前 AI Agent 读取知识库完成 brief.md / script.json / review.json，运行 hash/check')


def cmd_hash(a):
    root, knowledge = workspace(a.root)
    d = paths(root, a.id)
    sj = d/'script.json'
    if not sj.is_file():
        fail('请先由 当前 AI Agent 创建 script.json')
    print(json.dumps({'script_sha256':filehash(sj),
          'review_standard_sha256':filehash(knowledge/'review-rules.md')}, ensure_ascii=False, indent=2))


def check_script(d):
    script_path = d/'script.json'
    if not script_path.is_file():
        fail('缺少 script.json（不是 script.template.json），请由 当前 AI Agent 生成')
    j=load(script_path)
    if j.get('content_id') != d.name: fail('script.json 的 content_id 与目录不一致')
    for field in ('title','narration'):
        if not isinstance(j.get(field),str) or len(j[field].strip())<5: fail(f'script.{field} 必须是有效文本')
    shots=j.get('shots')
    if not isinstance(shots,list) or not shots: fail('script.shots 至少一个分镜')
    for shot in shots:
        if not isinstance(shot,dict) or not isinstance(shot.get('visual'),str) or not shot['visual'].strip():
            fail('每个分镜需要 visual 描述')
        if not isinstance(shot.get('seconds'),(int,float)) or shot['seconds'] <= 0:
            fail('每个分镜必须设置正数 seconds')
    if not isinstance(j.get('duration_seconds'),(int,float)) or (
            abs(sum(x['seconds'] for x in shots) - j['duration_seconds']) > 0.1):
        fail('分镜 seconds 总和与 duration_seconds 不一致，不能继续制作')
    if not isinstance(j.get('platforms'),dict): fail('platforms 必须是对象')
    for p in PLATFORMS:
        item=j['platforms'].get(p)
        if not isinstance(item,dict) or not item.get('title') or not isinstance(item.get('tags'),list):
            fail(f'平台 {p} 缺少 title 或 tags')
    return j


def cmd_check(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    j=check_script(d)
    result={'script_structure':'valid','script_sha256':filehash(d/'script.json')}
    try:
        ensure_reviewed_script(d,k)
        result['script_ready']='valid'
    except ValueError as e:
        result['script_ready']='not_ready: '+str(e)
    try:
        ensure_video_ready(d,k,root)
        result['video_ready']='valid'
    except ValueError as e:
        result['video_ready']='not_ready: '+str(e)
    print(json.dumps(result,ensure_ascii=False,indent=2))


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
    if out.exists() and not getattr(render_ffmpeg,'allow_replace',False): fail('成片已存在。重新渲染请显式加 --replace，之后需要重新审核')
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
    quality = inspect_video(ffmpeg, ffprobe, out, load(d/'script.json')['shots'])
    if quality['result'] != 'PASS':
        fail('生成 MP4 后发现异常配音，未登记成功渲染：' + '; '.join(quality['issues']))
    save(d/'video'/'render.json',{'engine':'ffmpeg','video_sha256':filehash(out),
         'script_sha256':filehash(d/'script.json'),'created_at_utc':now(),
         'clips':[str(x) for x in clips],'audio':str(audio) if audio else None,
         'subtitles':str(subtitles) if subtitles else None,'duration_seconds':float(result['format']['duration'])})
    return out


def cmd_voiceover(a):
    root, _ = workspace(a.root)
    d = paths(root, a.id)
    script = check_script(d)
    ffmpeg = load_ffmpeg_bin(root, 'ffmpeg')
    ffprobe = load_ffmpeg_bin(root, 'ffprobe')
    if not ffmpeg or not ffprobe:
        fail('合成配音需要 FFmpeg/ffprobe，不要手写采样率转换')
    output = d / 'work' / 'narration.wav'
    take_paths = [Path(x).expanduser().resolve() for x in a.takes]
    report = mix_takes(ffmpeg, ffprobe, script['shots'], take_paths, output, replace=a.replace)
    save(d/'work'/'voiceover-check.json', {
        **report, 'audio_sha256': filehash(output), 'script_sha256': filehash(d/'script.json'),
        'takes': [str(p) for p in take_paths], 'output': str(output), 'checked_at_utc': now()})
    print('VOICEOVER_READY:', output, '\\n', json.dumps(report, ensure_ascii=False))


def cmd_render(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    script=ensure_reviewed_script(d,k)
    if a.material_ids and a.materials:
        fail('--material-ids 与 --materials 只能选择一种')
    selected = []
    if a.material_ids:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from materials import resolve_ids
        selected = resolve_ids(root, a.material_ids)
        files = [Path(x['path']) for x in selected]
    else:
        files = [Path(x).expanduser().resolve() for x in (a.materials or [])]
    if not files: fail('请指定 --material-ids（从素材库选择）或 --materials（临时本地文件）')
    # Agent must verify the license/provenance before attesting, no human approval prompt.
    if not a.rights_confirmed: fail('必须传入 --rights-confirmed 表示已核对素材来源/授权（不代表工具自动校验版权）')
    for clip in files:
        if not clip.is_file(): fail('素材不存在：' + str(clip))
    if a.dry_run and a.engine == 'ffmpeg':
        print('DRY_RUN_NO_RENDER:', json.dumps({'engine': a.engine,
              'clips': [str(p) for p in files], 'indexed_assets': [x['id'] for x in selected]},
              ensure_ascii=False))
        return
    if a.engine=='ffmpeg':
        render_ffmpeg.allow_replace=a.replace
        result=render_ffmpeg(root,d,files,Path(a.audio).expanduser().resolve() if a.audio else None,
            Path(a.subtitles).expanduser().resolve() if a.subtitles else None, a.width,a.height)
        save(d/'video'/'materials-used.json',
             {'video_sha256': filehash(result), 'rights_acknowledged': True,
              'assets': selected if selected else
              [{'source': 'manual', 'path': str(p), 'rights': 'agent-verified-no-index'}
               for p in files]})
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
    root,k=workspace(a.root); d=paths(root,a.id); ensure_reviewed_script(d,k)
    src=Path(a.file).expanduser().resolve()
    if not src.is_file() or src.suffix.lower()!='.mp4': fail('只允许导入存在的 .mp4 视频文件')
    ffprobe = load_ffmpeg_bin(root, 'ffprobe')
    if not ffprobe: fail('缺少 ffprobe，无法验证导入的 MP4')
    info=json.loads(run([ffprobe,'-v','error','-show_streams','-show_format','-of','json',src]))
    streams=info.get('streams',[])
    if (not any(x.get('codec_type')=='video' for x in streams) or
            not any(x.get('codec_type')=='audio' for x in streams) or
            float(info.get('format',{}).get('duration',0))<=0):
        fail('导入的视频必须是有效的音视频 MP4')
    ffmpeg = load_ffmpeg_bin(root, 'ffmpeg')
    if not ffmpeg: fail('导入需要 FFmpeg 验证音频节奏')
    quality = inspect_video(ffmpeg, ffprobe, src, load(d/'script.json')['shots'])
    if quality['result'] != 'PASS':
        fail('导入 MP4 音频异常：' + '; '.join(quality['issues']))
    dst=video_path(d); dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists() and not a.replace: fail('已有成片，需要 --replace 明确覆盖')
    if src!=dst: shutil.copy2(src,dst)
    save(d/'video'/'render.json',{'engine':'import','source':str(src),'video_sha256':filehash(dst),
                                 'script_sha256':filehash(d/'script.json'),
                                 'duration_seconds':float(info['format']['duration']),'created_at_utc':now()})
    print('IMPORTED:',dst)


def cmd_package(a):
    root,k=workspace(a.root); d=paths(root,a.id)
    script=check_script(d)
    targets=list(PLATFORMS) if a.platform=='all' else [a.platform]
    # A seven-platform package must not decode the same MP4 five times.
    if any(p in VIDEO_PLATFORMS for p in targets): ensure_video_ready(d,k,root)
    if any(p not in VIDEO_PLATFORMS for p in targets): ensure_reviewed_script(d,k)
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
              'script_sha256':filehash(d/'script.json'),
              'video_sha256':filehash(video_path(d)) if p in VIDEO_PLATFORMS else None,
              'video_review_sha256':filehash(d/'video'/'review.json') if p in VIDEO_PLATFORMS else None,
              'video_path':str(video_path(d)) if p in VIDEO_PLATFORMS else None,
              'article_path':None,'generated_at_utc':now(), 'account_alias':None}
        target=d/'platforms'/p
        target.mkdir(parents=True,exist_ok=True)
        if article is not None:
            doc=target/'article.md'
            if doc.exists() and not a.replace: fail(f'{p} 文章已存在，使用 --replace 才能覆盖')
            doc.write_text(article or '(请由 当前 AI Agent 提供公众号/知乎适配图文)',encoding='utf-8')
            pack['article_path']=str(doc)
        # Updated packages invalidate older source hashes; actual submission remains scoped to the original task.
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
    p=a.platform
    if p not in PLATFORMS: fail('未知平台')
    task=load(d/'content.json')
    if a.execute and task.get('publish_targets',{}).get(p)!=a.account:
        fail('当前平台/账号未在初始任务中明确授权公开发布')
    packfile=d/'platforms'/p/'package.json'
    if not packfile.is_file(): fail('发布前必须生成并通过质量审核的发布包')
    pack=load(packfile)
    if (pack.get('content_id')!=a.id or pack.get('platform')!=p or
            pack.get('script_sha256')!=filehash(d/'script.json')):
        fail('发布包与当前脚本版本不一致，需要重新打包')
    if p in VIDEO_PLATFORMS:
        ensure_video_ready(d,k,root)
        if (pack.get('video_sha256')!=filehash(video_path(d)) or
                pack.get('video_review_sha256')!=filehash(d/'video'/'review.json')):
            fail('发布包与当前成片/AI 审核版本不一致，需要重新打包')
    else:
        ensure_reviewed_script(d,k)
    if p not in VIDEO_PLATFORMS:
        print(f'{p} 暂未接入经验证的自动投稿接口，已准备图文包：{pack.get("article_path")}')
        return
    cli=sau_binary(root)
    if not cli.is_file(): fail('未安装 social-auto-upload，先安装并验证免费投稿工具')
    tid=a.tid or pack.get('category_id')
    if p=='bilibili' and not tid:
        fail('B站缺少已核验分区 TID，请在平台配置提供 category_id 或使用 --tid')
    cmd=[cli,p,'upload-video','--account',a.account,'--file',video_path(d),
         '--title',pack['title'],'--desc',pack.get('description','')]
    if p=='bilibili': cmd.extend(['--tid',str(tid)])
    if pack.get('tags'): cmd.extend(['--tags',','.join(str(t) for t in pack['tags'])])
    if not a.execute:
        print('DRY_RUN_NO_UPLOAD:',subprocess.list2cmdline([str(x) for x in cmd]))
        return
    ledger_file=d/'publish-ledger.json'; ledger=load(ledger_file)
    previous=ledger.get('platforms',{}).get(p,{})
    if previous.get('state') in ('attempting','submitted_unknown','published'):
        fail('该平台已有尝试中/状态未知/已发布记录，禁止重复投稿；先核对平台状态')
    ledger['platforms'][p]={'state':'attempting','account':a.account,'at':now()}
    save(ledger_file,ledger)
    try:
        proc=subprocess.run([str(x) for x in cmd],cwd=cli.parent.parent,env=tool_env(root),
                            capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900)
        ledger['platforms'][p]={'state':'submitted_unknown','account':a.account,'returncode':proc.returncode,
            'at':now(),'note':'须核对平台作品链接；退出码不代表公开发布成功'}
        print('UPLOAD_SUBMITTED_STATUS_UNKNOWN:',proc.returncode)
    except (subprocess.TimeoutExpired, OSError) as exc:
        ledger['platforms'][p]={'state':'submitted_unknown','account':a.account,'at':now(),
            'note':'超时/异常，状态未知；禁止盲重试'}
        print('UPLOAD_STATUS_UNKNOWN:',type(exc).__name__)
    finally:
        save(ledger_file,ledger)


def cmd_confirm_published(a):
    root,_=workspace(a.root); d=paths(root,a.id)
    ledger_file=d/'publish-ledger.json'; ledger=load(ledger_file)
    prev=ledger['platforms'].get(a.platform,{})
    if prev.get('state')!='submitted_unknown': fail('仅允许确认已提交待核查状态')
    task=load(d/'content.json')
    if task.get('publish_targets',{}).get(a.platform)!=prev.get('account'):
        fail('发布状态必须属于初始任务中授权的平台和账号')
    expected_domains={
        'xiaohongshu': ('xiaohongshu.com','xhslink.com'),
        'douyin': ('douyin.com',),
        'tencent': ('weixin.qq.com',),
        'bilibili': ('bilibili.com','b23.tv'),
        'kuaishou': ('kuaishou.com',),
        'wechat_oa': ('mp.weixin.qq.com',),
        'zhihu': ('zhihu.com',),
    }
    url=urlsplit(a.url)
    host=(url.hostname or '').lower()
    if (url.scheme!='https' or url.username or url.password or not host or
            not any(host==d or host.endswith('.'+d) for d in expected_domains[a.platform])):
        fail('请提供当前平台真实作品的 HTTPS 链接，不能用其他网站代替')
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
    for key,fn in (('script_ready',ensure_reviewed_script),('video_ready',ensure_video_ready)):
        try:
            if key=='video_ready': fn(d,k,root)
            else: fn(d,k)
            result[key]=True
        except ValueError as e:result[key]=False;result[key+'_reason']=str(e)
    print(json.dumps(result,indent=2,ensure_ascii=False))


def parse():
    parser=argparse.ArgumentParser(description='AI Media Studio - 一次任务授权与 AI 自主质量闭环')
    parser.add_argument('--root',required=True,help='安装根目录（与 config/workspace.json 一致）')
    sub=parser.add_subparsers(dest='command',required=True)
    n=sub.add_parser('new');n.add_argument('--id',required=True);n.add_argument('--title',required=True)
    n.add_argument('--publish-target',action='append',help='仅在初始用户任务明确要求公开发布时填写 platform:account；可重复')
    n.add_argument('--task-ref',help='原始用户任务消息引用（有则记录，不包含凭据）')
    n.set_defaults(func=cmd_new)
    h=sub.add_parser('hash');h.add_argument('--id',required=True);h.set_defaults(func=cmd_hash)
    c=sub.add_parser('check');c.add_argument('--id',required=True);c.set_defaults(func=cmd_check)
    c=sub.add_parser('status');c.add_argument('--id',required=True);c.set_defaults(func=cmd_status)
    voice=sub.add_parser('voiceover');voice.add_argument('--id',required=True);voice.add_argument('--takes',nargs='+',required=True);voice.add_argument('--replace',action='store_true');voice.set_defaults(func=cmd_voiceover)
    ren=sub.add_parser('render');ren.add_argument('--id',required=True);ren.add_argument('--engine',choices=['ffmpeg','mpt'],default='ffmpeg');
    ren.add_argument('--materials',nargs='+',help='手动指定本地视频，兼容原流程')
    ren.add_argument('--material-ids',nargs='+',help='从 materials search 返回的素材 ID 按指定顺序剪辑')
    ren.add_argument('--audio');ren.add_argument('--subtitles');ren.add_argument('--rights-confirmed',action='store_true');ren.add_argument('--no-voice',action='store_true');ren.add_argument('--width',type=int,default=720);ren.add_argument('--height',type=int,default=1280);ren.add_argument('--replace',action='store_true');ren.add_argument('--dry-run',action='store_true');ren.set_defaults(func=cmd_render)
    ip=sub.add_parser('import-video');ip.add_argument('--id',required=True);ip.add_argument('--file',required=True);ip.add_argument('--replace',action='store_true');ip.set_defaults(func=cmd_import_video)
    pkg=sub.add_parser('package');pkg.add_argument('--id',required=True);pkg.add_argument('--platform',choices=['all',*PLATFORMS],default='all');pkg.add_argument('--replace',action='store_true');pkg.set_defaults(func=cmd_package)
    pub=sub.add_parser('publish');pub.add_argument('--id',required=True);pub.add_argument('--platform',required=True,choices=PLATFORMS);pub.add_argument('--account',required=True);pub.add_argument('--tid',help='B站视频分区ID');pub.add_argument('--execute',action='store_true');pub.set_defaults(func=cmd_publish)
    verify=sub.add_parser('confirm-published');verify.add_argument('--id',required=True);verify.add_argument('--platform',required=True,choices=PLATFORMS);verify.add_argument('--url',required=True);verify.add_argument('--who',default='agent-verified');verify.set_defaults(func=cmd_confirm_published)
    return parser.parse_args()


def main():
    a=parse()
    try: a.func(a);return 0
    except (ValueError,FileNotFoundError,RuntimeError,json.JSONDecodeError,subprocess.TimeoutExpired) as e:
        print('ERROR:',str(e),file=sys.stderr);return 2


if __name__=='__main__': raise SystemExit(main())