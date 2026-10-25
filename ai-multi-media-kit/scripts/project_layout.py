"""Human-first layout for new projects. Existing root-level projects remain unchanged."""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import re
import shutil
from pathlib import Path

ENGINE="99-专业工程"
SCRIPT_DIR="01-文案与分镜"
MEDIA_DIR="02-媒体素材"
HISTORY_DIR="03-修改与版本"
CATEGORIES={"image":"图片","audio":"配音","video":"视频片段","bgm":"背景音乐","sound":"音效"}
SEGMENT=re.compile(r"^### 镜头 (\d{2})\s*$",re.M)
FIELD=re.compile(r"^- (时长|画面标题|画面提示|画面描述|口播|图片|视频|配音)：(.*)$",re.M)
SCENE_FIELDS={"时长","画面标题","画面提示","画面描述","口播","图片","视频","配音"}


def project_root(d:Path)->Path:
    d=Path(d)
    return d.parent if d.name==ENGINE else d


def engine_dir(project:Path)->Path:
    p=Path(project)
    engine=p/ENGINE
    if engine.is_symlink() or (engine.exists() and not engine.resolve().is_relative_to(p.resolve())):
        raise ValueError("专业工程目录不可指向项目外部")
    return engine if (engine/"content.json").is_file() else p


def modern(d:Path)->bool:
    return Path(d).name==ENGINE


def project_id(d:Path)->str:
    return project_root(d).name


def video_file(d:Path)->Path:
    return project_root(d)/"成品视频.mp4" if modern(d) else d/"video"/"master.mp4"


def narration_file(d:Path)->Path:
    return project_root(d)/MEDIA_DIR/"配音"/"完整旁白.wav" if modern(d) else d/"work"/"narration.wav"


def story_file(d:Path)->Path:
    return project_root(d)/SCRIPT_DIR/"分镜脚本.md"


def digest(file:Path)->str:
    return hashlib.sha256(Path(file).read_bytes()).hexdigest()


def create_project(project:Path)->Path:
    project.mkdir(parents=True,exist_ok=False)
    engine=project/ENGINE
    engine.mkdir()
    for sub in CATEGORIES.values():
        (project/MEDIA_DIR/sub).mkdir(parents=True)
    (project/SCRIPT_DIR).mkdir()
    (project/HISTORY_DIR).mkdir()
    (project/"打开这里.md").write_text(
        "# 作品目录\n\n"
        "直接播放根目录的 **成品视频.mp4**；**视频封面.png** 可用于发布时选取封面（制作完成后出现）。\n\n"
        "- **01-文案与分镜/**：浏览和修改分镜。修改后请让 Agent 执行 studio storyboard --apply 同步工程，再重新渲染，改 Markdown 不会自动更新 MP4。\n"
        "- **02-媒体素材/**：这里保存实际参与制作的图片、视频片段、配音、背景音乐和音效。\n"
        "- **03-修改与版本/**：保留修改记录和必要的旧版本。\n"
        "- **99-专业工程/**：渲染源码、依赖及校验记录，普通用户无需进入。\n\n"
        "修改后的成片需重新检查字幕、音轨与验收版本。\n",encoding="utf8")
    (project/SCRIPT_DIR/"视频文案.md").write_text(
        "# 视频文案\n\n完整口播与镜头顺序统一维护在 [分镜脚本.md](分镜脚本.md) 的“口播”字段。\n"
        "不复制另一份容易失去同步的口播原文。\n",encoding="utf8")
    (project/SCRIPT_DIR/"分镜脚本.md").write_text(
        "# 分镜脚本\n\n完成制作脚本后生成镜头列表，用户可编辑时长、画面与素材。\n",encoding="utf8")
    (project/HISTORY_DIR/"修改记录.md").write_text("# 修改记录\n\n- 创建新项目。\n",encoding="utf8")
    # Establish ownership of the empty user-facing documents immediately.
    # If the user edits either one before the Agent generates script.json,
    # the first export must not silently erase their notes.
    initial={"md_sha256":digest(story_file(engine)),
             "overview_sha256":digest(_overview(engine))}
    _manifest(engine).write_text(json.dumps(initial,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    return engine


def _clean(value):
    return str(value or "").replace("\r"," ").replace("\n"," ").strip()


def _display_asset(value:str|None)->str:
    return "../"+MEDIA_DIR+"/"+value.replace("\\","/") if value else "无"


def _resolve_asset(d:Path,value:str,kind:str)->str|None:
    value=value.strip()
    if not value or value=="无":
        return None
    if Path(value).is_absolute():
        raise ValueError("分镜素材只能引用项目媒体目录的相对路径")
    project=project_root(d).resolve()
    assets=(project/MEDIA_DIR).resolve()
    if not assets.is_relative_to(project):
        raise ValueError("媒体目录不得指向项目外部")
    item=(project/SCRIPT_DIR/value).resolve()
    if not item.is_relative_to(assets) or not item.is_file():
        raise ValueError("分镜素材不存在或越过媒体素材目录："+value)
    rel=item.relative_to(assets).as_posix()
    if not rel.startswith(CATEGORIES[kind]+"/"):
        raise ValueError("素材类别不正确："+rel)
    return rel


def _manifest(d:Path)->Path:
    return d/"user-storyboard.json"


def _overview(d:Path)->Path:
    return project_root(d)/SCRIPT_DIR/"视频文案.md"


def _overview_text(script:dict)->str:
    full=script.get("narration") or "".join(x.get("voiceover","") for x in script.get("shots",[]))
    return ("# 视频文案\n\n"
            "本页方便直接阅读完整口播，内容从分镜自动汇总。**修改请进入 [分镜脚本.md](分镜脚本.md) 的各镜头“口播”字段**；"
            "仅修改此页不会更改配音或成片。\n\n"
            "## 完整口播\n\n"+full.strip()+"\n")


def _check_overview(d:Path,meta:dict)->None:
    old_sha=meta.get("overview_sha256")
    if old_sha and (not _overview(d).is_file() or digest(_overview(d))!=old_sha):
        raise ValueError("视频文案.md 被单独修改，请先把内容合并到 分镜脚本.md 的口播字段，拒绝覆盖用户修改")


def check_storyboard(d:Path):
    if not modern(d) or not _manifest(d).is_file():
        return
    meta=json.loads(_manifest(d).read_text(encoding="utf8"))
    _check_overview(d,meta)
    file=story_file(d)
    if not file.is_file() or digest(file)!=meta.get("md_sha256"):
        raise ValueError("中文分镜有未同步的修改，请先执行 studio storyboard --apply")


def export_storyboard(d:Path)->Path|None:
    if not modern(d) or not (d/"script.json").is_file():
        return None
    check_storyboard(d)
    script=json.loads((d/"script.json").read_text(encoding="utf8"))
    rendered=json.loads((d/"shotlist.json").read_text(encoding="utf8")) if (d/"shotlist.json").is_file() else {}
    items=rendered.get("shots",[])
    lines=["# 分镜脚本","","修改镜头后执行 studio rebuild --id <内容ID>，由 Agent 同步分镜、重渲并归档原视频。","",
           "- 连续旁白："+_display_asset(rendered.get("narration_audio")),""]
    timeline=0.0
    fps=rendered.get("fps",30)
    for i,shot in enumerate(script.get("shots",[]),1):
        scene=items[i-1] if i<=len(items) else {}
        seconds=float(shot["seconds"])
        start=round(timeline*fps)
        end=start+max(1,round(seconds*fps))
        lines += [f"### 镜头 {i:02d}",
            f"- 时间位置：{timeline:.2f}s～{timeline+seconds:.2f}s（第{start}～{end-1}帧 / {fps}fps；由程序计算）",
            f"- 时长：{seconds:g} 秒",
            f"- 画面标题：{_clean(scene.get('title') or shot.get('title'))}",
            f"- 画面提示：{_clean(scene.get('caption') or shot.get('caption'))}",
            f"- 画面描述：{_clean(shot.get('visual'))}",
            f"- 口播：{_clean(shot.get('voiceover'))}",
            f"- 图片：{_display_asset(scene.get('image'))}",
            f"- 视频：{_display_asset(scene.get('video'))}",
            f"- 配音：{_display_asset(scene.get('audio'))}",""]
        timeline+=seconds
    file=story_file(d)
    file.write_text("\n".join(lines).rstrip()+"\n",encoding="utf8")
    _overview(d).write_text(_overview_text(script),encoding="utf8")
    meta={"md_sha256":digest(file),"overview_sha256":digest(_overview(d)),
          "script_sha256":digest(d/"script.json")}
    if (d/"shotlist.json").is_file():
        meta["shotlist_sha256"]=digest(d/"shotlist.json")
    _manifest(d).write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    return file


def parse_storyboard(d:Path)->list[dict]:
    data=story_file(d).read_text(encoding="utf8")
    positions=list(SEGMENT.finditer(data))
    if not positions:
        raise ValueError("分镜文档缺少 ### 镜头 01")
    scenes=[]
    for i,m in enumerate(positions,1):
        if int(m.group(1))!=i:
            raise ValueError("分镜编号不连续或重复")
        end=positions[i].start() if i<len(positions) else len(data)
        values={}
        for k,value in FIELD.findall(data[m.end():end]):
            if k in values:raise ValueError("分镜字段重复："+k)
            values[k]=value.strip()
        # v0.13 Chinese storyboards had no separate video-footage field.
        # Treat it as optional for old projects; new exports always include it.
        required=SCENE_FIELDS-{"视频"}
        if not required.issubset(values) or not set(values).issubset(SCENE_FIELDS):
            raise ValueError(f"镜头 {i:02d} 分镜字段缺少或未知：{sorted(required-set(values))}")
        match=re.fullmatch(r"(\d+(?:\.\d+)?)\s*秒",values["时长"])
        if not match:raise ValueError("时长必须采用 n 秒格式")
        seconds=float(match.group(1))
        if not 0.5<=seconds<=120:raise ValueError("镜头时长不合理")
        image=_resolve_asset(d,values["图片"],"image")
        footage=_resolve_asset(d,values.get("视频","无"),"video")
        if image and footage:raise ValueError(f"镜头 {i:02d} 图片和视频不能同时使用")
        scenes.append(dict(seconds=seconds,title=values["画面标题"],
                           caption=values["画面提示"],visual=values["画面描述"],
                           voiceover=values["口播"],image=image,video=footage,
                           audio=_resolve_asset(d,values["配音"],"audio")))
    return scenes


def _backup(d:Path,names:list[str])->Path:
    dest=d/"history"/("工程备份-"+datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f"))
    dest.mkdir(parents=True,exist_ok=False)
    for n in names:
        if (d/n).is_file():shutil.copy2(d/n,dest/n)
    return dest


def apply_storyboard(d:Path)->dict:
    if not modern(d) or not (d/"script.json").is_file():
        raise ValueError("仅支持新式项目同步已有分镜；旧项目保持原结构")
    baseline=json.loads(_manifest(d).read_text(encoding="utf8")) if _manifest(d).is_file() else {}
    _check_overview(d,baseline)
    scenes=parse_storyboard(d)
    raw=story_file(d).read_text(encoding="utf8")
    master_match=re.search(r"^- 连续旁白：(.*)$",raw,re.M)
    new_master=_resolve_asset(d,master_match.group(1),"audio") if master_match else None
    current_script=d/"script.json"
    current_shots=d/"shotlist.json"
    marker=_manifest(d)
    if marker.is_file():
        baseline=json.loads(marker.read_text(encoding="utf8"))
        if baseline.get("script_sha256") != digest(current_script) or (baseline.get("shotlist_sha256") and
                (not current_shots.is_file() or baseline["shotlist_sha256"]!=digest(current_shots))):
            raise ValueError("中文分镜与专业工程均有独立修改，拒绝覆盖。请先核对冲突并由 Agent 合并版本")
    script=json.loads(current_script.read_text(encoding="utf8"))
    if len(scenes)!=len(script.get("shots",[])):
        raise ValueError("更改镜头数量请由 Agent 同步源码后重新生成分镜")
    renderfile=d/"shotlist.json"
    render=json.loads(renderfile.read_text(encoding="utf8")) if renderfile.is_file() else None
    if render and len(render.get("shots",[]))!=len(scenes):
        raise ValueError("分镜数量与 Remotion 时间轴不同")
    if render and master_match:render["narration_audio"]=new_master
    for i,(s,old) in enumerate(zip(scenes,script["shots"])):
        old.update(seconds=s["seconds"],title=s["title"],caption=s["caption"],
                   visual=s["visual"],voiceover=s["voiceover"])
        if render:
            render["shots"][i].update(seconds=s["seconds"],
                frames=round(s["seconds"]*render.get("fps",30)),
                title=s["title"],caption=s["caption"],voiceover=s["voiceover"],
                image=s["image"],video=s["video"],audio=s["audio"])
    script["duration_seconds"]=sum(s["seconds"] for s in scenes)
    script["narration"]="".join(s["voiceover"] for s in scenes) or script["title"]
    same=json.loads((d/"script.json").read_text(encoding="utf8"))==script
    if render:
        same=same and json.loads(renderfile.read_text(encoding="utf8"))==render
    if same:
        # Formatting/comment-only Markdown edits need no engine rewrite or fake revision.
        meta={"md_sha256":digest(story_file(d)),"overview_sha256":digest(_overview(d)),
              "script_sha256":digest(d/"script.json")}
        if render:meta["shotlist_sha256"]=digest(renderfile)
        _manifest(d).write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
        return {"changed":False,"backup":None}
    backup=_backup(d,["script.json","shotlist.json","user-storyboard.json"])
    (d/"script.json").write_text(json.dumps(script,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    if render:renderfile.write_text(json.dumps(render,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    _overview(d).write_text(_overview_text(script),encoding="utf8")
    meta={"md_sha256":digest(story_file(d)),"overview_sha256":digest(_overview(d)),
          "script_sha256":digest(d/"script.json")}
    if render:meta["shotlist_sha256"]=digest(renderfile)
    _manifest(d).write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
    with (project_root(d)/HISTORY_DIR/"修改记录.md").open("a",encoding="utf8") as f:
        f.write(f"\n- {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}：同步用户分镜。专业工程历史备份位于 99-专业工程/history/{backup.name}；旧视频审核失效。\n")
    return {"changed":True,"backup":str(backup)}


def store_asset(d:Path,source:Path,kind:str,index:int|None=None)->Path:
    src=Path(source).expanduser().resolve()
    if not modern(d):return src
    if not src.is_file():raise ValueError("素材不存在："+str(src))
    folder=project_root(d)/MEDIA_DIR/CATEGORIES[kind]
    if not folder.resolve().is_relative_to(project_root(d).resolve()):
        raise ValueError("媒体目录不能链接到项目外部")
    if src.is_relative_to(folder.resolve()):return src
    with src.open("rb") as stream:
        h=hashlib.sha256()
        for block in iter(lambda:stream.read(1024*1024),b""):
            h.update(block)
    stamp=h.hexdigest()[:10]
    # Same content is one asset even when reused in multiple shots.
    for item in folder.glob(f"*-{stamp}{src.suffix.lower()}"):
        if not item.resolve().is_relative_to(folder.resolve()):
            raise ValueError("素材库包含指向外部的链接，拒绝使用")
        if digest(item)==digest(src):return item
    filename=(f"镜头-{index:02d}" if index is not None else "素材")+f"-{stamp}{src.suffix.lower()}"
    target=folder/filename
    if target.is_file():
        if not target.resolve().is_relative_to(folder.resolve()):
            raise ValueError("同名素材指向外部，拒绝覆盖")
        if digest(target)!=digest(src):raise ValueError("素材文件名冲突")
    else:shutil.copy2(src,target)
    return target


def relative_media(d:Path,file:Path)->str:
    return file.resolve().relative_to((project_root(d)/MEDIA_DIR).resolve()).as_posix()


def archive_video(d:Path):
    file=video_file(d)
    if not modern(d) or not file.is_file():return None
    dest=project_root(d)/HISTORY_DIR/("旧成片-"+datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")+".mp4")
    shutil.copy2(file,dest)
    return dest
