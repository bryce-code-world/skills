<div align="center">

[中文](./README.md) · **English**

# ⚡ Bryce Skills

Practical skills built for collaboration between a person and AI.

</div>

Each skill starts from a real personal workflow and is then refined into reusable, open instructions.

This repository follows the standard `SKILL.md` directory structure.

## Skills

| Skill | Purpose |
|---|---|
| [Lightning](./lightning/SKILL.md) | Reshape internal documents for fast human reading and clear AI action without losing critical information. |
| [Writing Style](./writing-style/SKILL.md) | Extract, manage, select, and apply a stable, recognizable writing voice. |
| [Broadcast](./broadcast/SKILL.md) | Turn a clear content kernel into public posts for WeChat, Zhihu, and Xiaohongshu, with optional draft handoff to Wechatsync. |

## Installation

Ask an agent that supports `SKILL.md` to install:

```text
Install this skill:
https://github.com/bryce-code-world/skills/tree/main/lightning
```

You can also copy the `lightning` directory into your local skills directory.

For Writing Style, replace the link or directory name with `writing-style`.

For Broadcast, replace the link or directory name with `broadcast`.

## Lightning

Use it for:

- Creating, editing, restructuring, or reviewing internal documents.
- Analysis reports, design proposals, review reports, and task briefs.
- Turning raw notes or knowledge-base material into clear documents.
- Preparing task context that both you and AI can understand quickly.

Do not use it for news, blogs, papers, marketing copy, literary writing, or author-style imitation.

Core principle:

> Preserve every critical fact, then present the content in the easiest form to understand.

Example:

```text
Use $lightning to restructure this internal document.
```

## Writing Style

Use it for:

- Extracting your own or another author's high-level style from conversations or writing samples.
- Managing multiple named personal profiles and one default profile.
- Selecting a main style and scene-appropriate tone.
- Applying style and checking consistency across platforms.

It does not silently learn or change profiles, impersonate reference authors, invent experiences, or alter facts for style.

Example:

```text
Use $writing-style to extract my personal style from these articles. Show the candidate profile and wait for confirmation before saving it.
```

## Broadcast

Use it for:

- Creating standard WeChat articles or card-based WeChat posts from one content kernel.
- Creating Zhihu answers or standalone articles.
- Creating short or long Xiaohongshu card posts.
- Handing an accepted publishing package to the official Wechatsync adapter after explicit authorization.

It preserves facts, viewpoints, conditions, and uncertainty. By default, it does not connect accounts, save drafts, or publish anything.

Example:

```text
Use $broadcast to turn this content into a standard WeChat article and a long Xiaohongshu card post.
```

## License

[MIT](./LICENSE)
