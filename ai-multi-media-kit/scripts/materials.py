#!/usr/bin/env python3
"""Local video source registry and index. No network, LLM calls, or publishing."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

EXTENSIONS = {".mp4", ".mov", ".mkv", ".webm", ".m4v", ".avi"}
RIGHTS = ("unverified", "owned", "licensed")
SOURCE_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,63}$")
MAX_FILES = 10000


def fail(msg):
    raise ValueError(msg)


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(tmp, path)


def workspace(root):
    root = Path(root).expanduser().resolve()
    cfg = root / "config" / "workspace.json"
    if not cfg.is_file():
        fail("工作区尚未初始化")
    data = read(cfg)
    if Path(data["install_root"]).resolve() != root:
        fail("当前工作区配置路径不匹配")
    knowledge = Path(data["knowledge_root"]).expanduser().resolve()
    if not knowledge.is_dir():
        fail("企业知识库目录不可访问")
    return root, knowledge


def registry_path(root):
    return root / "config" / "material-sources.json"


def index_path(root):
    return root / "runtime" / "materials-index.json"


def ensure_registry(root, knowledge):
    path = registry_path(root)
    if not path.is_file():
        default = {
            "schema": 1,
            "sources": [{"name": "company-library", "path": str(knowledge / "materials"),
                         "rights": "unverified", "license_note": ""}]
        }
        write(path, default)
    return read(path)


def load_index(root):
    p = index_path(root)
    return read(p) if p.is_file() else {"schema": 1, "items": []}


def video_file(path):
    return path.suffix.lower() in EXTENSIONS


def asset_id(source, path):
    normalized = os.path.normcase(str(path.resolve()))
    return hashlib.sha256((source + "\0" + normalized).encode("utf-8")).hexdigest()[:20]


def tags(raw):
    return list(dict.fromkeys(t.strip() for t in re.split("[,，]", raw or "") if t.strip()))


def checked_url(raw):
    if not raw:
        return ""
    try:
        u = urlsplit(raw)
    except ValueError:
        fail("素材来源 URL 无效")
    if (u.scheme != "https" or not u.hostname or u.username or u.password
            or u.query or u.fragment):
        fail("来源 URL 只能是无凭据、无查询参数的 HTTPS 链接（避免记录 Token）")
    return raw


def check_rights(rights, note):
    if rights not in RIGHTS:
        fail("未知素材授权状态")
    if rights == "licensed" and not (note or "").strip():
        fail("授权素材必须记录授权凭据或协议说明 --license-note")


def make_entry(source, path, *, rights="unverified", note="", tags_value=None, description="", source_url=""):
    check_rights(rights, note)
    path = path.expanduser().resolve()
    if not path.is_file() or path.is_symlink() or not video_file(path):
        fail("不是有效的本地视频素材：" + str(path))
    st = path.stat()
    return {
        "id": asset_id(source, path), "source": source, "path": str(path),
        "name": path.name, "size": st.st_size, "mtime_ns": st.st_mtime_ns,
        "tags": tags_value or [], "description": description,
        "rights": rights, "license_note": note, "source_url": checked_url(source_url)
    }


def by_id(root, value):
    items = load_index(root).get("items", [])
    match = next((x for x in items if x["id"] == value), None)
    if match is None:
        fail("素材未索引：" + value)
    return match


def fresh_path(item):
    p = Path(item["path"])
    if not p.is_file() or p.is_symlink() or not video_file(p):
        fail("素材丢失或不是可用视频：" + item["id"])
    st = p.stat()
    if st.st_size != item["size"] or st.st_mtime_ns != item["mtime_ns"]:
        fail("素材已变化，请重新执行 scan/add-file：" + item["id"])
    return p


def resolve_ids(root, ids):
    """Return validated, licensed local assets; does not copy any files."""
    if len(set(ids)) != len(ids):
        fail("素材 ID 重复")
    selected = []
    for material_id in ids:
        item = by_id(root, material_id)
        if item.get("rights") not in ("owned", "licensed"):
            fail("素材授权未核实，先 annotate 记录授权来源：" + material_id)
        check_rights(item["rights"], item.get("license_note", ""))
        fresh_path(item)
        selected.append(item)
    if not selected:
        fail("至少提供一个素材 ID")
    return selected


def cmd_sources(a, root, knowledge):
    print(json.dumps(ensure_registry(root, knowledge), ensure_ascii=False, indent=2))


def cmd_add_source(a, root, knowledge):
    if not SOURCE_NAME.fullmatch(a.name):
        fail("来源名称仅允许英文、数字、-、_，且英文开头")
    path = Path(a.path).expanduser().resolve()
    if not path.is_dir():
        fail("素材目录不存在或尚未挂载：" + str(path))
    check_rights(a.rights, a.license_note)
    reg = ensure_registry(root, knowledge)
    if any(s["name"].casefold() == a.name.casefold() for s in reg["sources"]):
        fail("素材来源已存在：" + a.name)
    reg["sources"].append({"name": a.name, "path": str(path),
                           "rights": a.rights, "license_note": a.license_note})
    write(registry_path(root), reg)
    print("ADDED_SOURCE", a.name, str(path))


def cmd_scan(a, root, knowledge):
    reg = ensure_registry(root, knowledge)
    sources = [s for s in reg["sources"] if not a.source or s["name"] == a.source]
    if not sources:
        fail("素材来源不存在：" + str(a.source))
    existing = load_index(root).get("items", [])
    replaced = {s["name"] for s in sources}
    items = [i for i in existing if i["source"] not in replaced]
    old = {i["id"]: i for i in existing}
    count = 0
    for src in sources:
        base = Path(src["path"])
        if not base.is_dir():
            fail("素材来源目录不可访问，未保存索引：" + str(base))
        for dirname, dirs, filenames in os.walk(base, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(dirname) / d).is_symlink()]
            for filename in sorted(filenames):
                p = Path(dirname) / filename
                if p.is_symlink() or not video_file(p):
                    continue
                count += 1
                if count > MAX_FILES:
                    fail(f"扫描超过 {MAX_FILES} 个视频，请缩小素材目录；未写入索引")
                material_id = asset_id(src["name"], p)
                prior = old.get(material_id, {})
                # Keep human annotations across scans; source default only for unannotated entries.
                own_rights = prior.get("rights") if prior.get("rights_overridden") else src.get("rights", "unverified")
                own_note = prior.get("license_note") if prior.get("rights_overridden") else src.get("license_note", "")
                item = make_entry(src["name"], p, rights=own_rights, note=own_note,
                                  tags_value=prior.get("tags", []), description=prior.get("description", ""),
                                  source_url=prior.get("source_url", ""))
                if prior.get("rights_overridden"):
                    item["rights_overridden"] = True
                items.append(item)
    write(index_path(root), {"schema": 1, "items": items})
    print(json.dumps({"indexed_from_scan": count, "total_indexed": len(items),
                      "sources": sorted(replaced)}, ensure_ascii=False))


def cmd_add_file(a, root, knowledge):
    p = Path(a.path).expanduser()
    if p.is_symlink():
        fail("不能登记符号链接素材")
    item = make_entry("one-off", p, rights=a.rights, note=a.license_note,
                      tags_value=tags(a.tags), description=a.description,
                      source_url=a.source_url)
    data = load_index(root)
    if any(x["id"] == item["id"] for x in data["items"]):
        fail("文件已登记；要修改信息请使用 annotate")
    data["items"].append(item)
    write(index_path(root), data)
    print(json.dumps(item, ensure_ascii=False, indent=2))


def cmd_annotate(a, root, knowledge):
    data = load_index(root)
    entry = next((item for item in data["items"] if item["id"] == a.id), None)
    if entry is None:
        fail("素材 ID 不存在：" + a.id)
    if a.tags is not None:
        entry["tags"] = tags(a.tags)
    if a.description is not None:
        entry["description"] = a.description
    if a.rights is not None:
        entry["rights"] = a.rights
        entry["rights_overridden"] = True
    if a.license_note is not None:
        entry["license_note"] = a.license_note
    if a.source_url is not None:
        entry["source_url"] = checked_url(a.source_url)
    check_rights(entry["rights"], entry.get("license_note", ""))
    write(index_path(root), data)
    print(json.dumps(entry, ensure_ascii=False, indent=2))


def cmd_search(a, root, knowledge):
    words = a.query.casefold().split()
    ranked = []
    for item in load_index(root).get("items", []):
        haystack = " ".join([item["name"], item.get("description", ""),
                             " ".join(item.get("tags", []))]).casefold()
        match = sum(1 for word in words if word in haystack)
        if not words or match:
            ranked.append((match, item))
    ranked.sort(key=lambda row: (-row[0], row[1]["name"], row[1]["id"]))
    print(json.dumps({"search_type": "filename_tags_description_not_visual_ai",
                      "items": [item for _, item in ranked[:a.limit]]}, ensure_ascii=False, indent=2))


def cmd_resolve(a, root, knowledge):
    print(json.dumps({"items": resolve_ids(root, a.ids)}, ensure_ascii=False, indent=2))


def cmd_preview(a, root, knowledge):
    item = by_id(root, a.id)
    path = fresh_path(item)
    ffmpeg = root / "tools" / "ffmpeg" / "bin" / ("ffmpeg.exe" if os.name == "nt" else "ffmpeg")
    exe = str(ffmpeg) if ffmpeg.is_file() else shutil.which("ffmpeg")
    if not exe:
        fail("缺少 FFmpeg，无法提取预览帧")
    out = root / "runtime" / "material-previews" / (a.id + ".jpg")
    out.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([exe, "-hide_banner", "-loglevel", "error", "-y",
                             "-i", str(path), "-vf", "thumbnail,scale=640:-2",
                             "-frames:v", "1", str(out)], capture_output=True, timeout=120)
    if result.returncode or not out.is_file():
        fail("预览帧提取失败（检查文件格式或损坏情况）")
    print("PREVIEW", out)


def cmd_fetch_online(a, root, knowledge):
    """Opt-in stock-footage retrieval via installed MPT; NEVER reaches its video/post stage."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import studio  # Lazily import the existing human approval guard.
    d = studio.paths(root, a.id)
    script = studio.ensure_approved_script(d, knowledge)
    terms = a.terms.strip()
    if not terms or len(terms) > 400 or "\n" in terms or "\r" in terms:
        fail("素材检索关键词必须是 1～400 字符的单行文本，优先由 当前 AI Agent 从分镜生成")
    cmd_preview = ["<mpt-managed-python>", "cli.py", "--video-script", "<approved-script>",
                   "--video-terms", terms, "--video-source", a.provider,
                   "--voice-name", "no-voice", "--no-subtitle-enabled", "--stop-at", "materials"]
    if not a.execute:
        print(json.dumps({"status": "PLAN_ONLY_NO_NETWORK", "provider": a.provider,
                          "command_preview": cmd_preview,
                          "next": "核对第三方 API 配额与素材许可，再 --execute 并由本人确认"},
                         ensure_ascii=False, indent=2))
        return
    mpt = root / "tools" / "MoneyPrinterTurbo"
    py = mpt / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not py.is_file() or not (mpt / "cli.py").is_file():
        fail("MoneyPrinterTurbo 未安装，不能联网获取素材；先执行 installer --component mpt")
    confirmation = f"FETCH:{a.id}:{a.provider}"
    if input(f"将联网调用 {a.provider} 素材服务。请用户本人输入 {confirmation} ：").strip() != confirmation:
        fail("用户未授权联网素材获取")
    cmd = [str(py), "cli.py", "--video-script", script["narration"],
           "--video-terms", terms, "--video-source", a.provider,
           "--voice-name", "no-voice", "--no-subtitle-enabled", "--stop-at", "materials"]
    result = subprocess.run(cmd, cwd=mpt, env=studio.tool_env(root),
                            capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=1200)
    if result.returncode != 0:
        fail(f"MPT 素材获取失败（退出码 {result.returncode}）；请在本地 MPT 日志核查，可能需要提供商 API Key")
    print("MPT_STOCK_MATERIAL_STAGE_FINISHED")
    print("请在 MoneyPrinterTurbo/storage/tasks/ 中检查实际素材及原始来源/许可。")
    print("将许可合规的文件使用 materials add-file 登记后再编入成片。此命令未执行视频合成或投稿。")


def parse():
    parser = argparse.ArgumentParser(description="本地/NAS视频素材源管理（不联网）")
    parser.add_argument("--root", required=True)
    subs = parser.add_subparsers(dest="command", required=True)
    s = subs.add_parser("sources")
    s.set_defaults(func=cmd_sources)
    s = subs.add_parser("add-source")
    s.add_argument("--name", required=True)
    s.add_argument("--path", required=True)
    s.add_argument("--rights", choices=RIGHTS, default="unverified")
    s.add_argument("--license-note", default="")
    s.set_defaults(func=cmd_add_source)
    s = subs.add_parser("scan")
    s.add_argument("--source")
    s.set_defaults(func=cmd_scan)
    s = subs.add_parser("add-file")
    s.add_argument("--path", required=True)
    s.add_argument("--rights", choices=RIGHTS, default="unverified")
    s.add_argument("--license-note", default="")
    s.add_argument("--source-url", default="")
    s.add_argument("--tags", default="")
    s.add_argument("--description", default="")
    s.set_defaults(func=cmd_add_file)
    s = subs.add_parser("annotate")
    s.add_argument("--id", required=True)
    s.add_argument("--rights", choices=RIGHTS)
    s.add_argument("--license-note")
    s.add_argument("--source-url")
    s.add_argument("--tags")
    s.add_argument("--description")
    s.set_defaults(func=cmd_annotate)
    s = subs.add_parser("search")
    s.add_argument("--query", default="")
    s.add_argument("--limit", type=int, default=20)
    s.set_defaults(func=cmd_search)
    s = subs.add_parser("resolve")
    s.add_argument("--ids", nargs="+", required=True)
    s.set_defaults(func=cmd_resolve)
    s = subs.add_parser("preview")
    s.add_argument("--id", required=True)
    s.set_defaults(func=cmd_preview)
    s = subs.add_parser("fetch-online")
    s.add_argument("--id", required=True, help="已经人工批准的脚本 ID")
    s.add_argument("--provider", required=True, choices=("pexels", "pixabay", "coverr"))
    s.add_argument("--terms", required=True, help="当前 AI Agent 从分镜生成的素材关键词")
    s.add_argument("--execute", action="store_true", help="联网操作；另需用户本人交互确认")
    s.set_defaults(func=cmd_fetch_online)
    a = parser.parse_args()
    if getattr(a, "limit", 1) < 1 or getattr(a, "limit", 1) > 100:
        parser.error("--limit 范围 1～100")
    return a


def main():
    a = parse()
    try:
        root, knowledge = workspace(a.root)
        a.func(a, root, knowledge)
        return 0
    except (ValueError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
        print("ERROR:", exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
