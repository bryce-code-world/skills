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
| [Hello](./hello/SKILL.md) | Build and maintain a user-controlled personal context profile through ongoing interviews and staged discoveries. |
| [Lightning](./lightning/SKILL.md) | Reshape internal documents for fast human reading and clear AI action without losing critical information. |
| [Visual Cognitive Learning](./visual-cognitive-learning/SKILL.md) | Translate a clear source document into a guided, offline single-file HTML learning model that ends with the whole picture. |
| [Writing Style](./writing-style/SKILL.md) | Extract, manage, select, and apply a stable, recognizable writing voice. |
| [Broadcast](./broadcast/SKILL.md) | Turn a clear content kernel into a complete visual longform base article, then adapt it for WeChat or Zhihu. |

## Installation

Ask an agent that supports `SKILL.md` to install:

```text
Install this skill:
https://github.com/bryce-code-world/skills/tree/main/lightning
```

You can also copy the `lightning` directory into your local skills directory.

For Hello, replace the link or directory name with `hello`.

For Visual Cognitive Learning, replace the link or directory name with `visual-cognitive-learning`.

For Writing Style, replace the link or directory name with `writing-style`.

For Broadcast, replace the link or directory name with `broadcast`.

The five skills install independently. A skill asks once before installing a missing dependency, and only when the current task actually needs it.

Each skill checks for its own updates at most once every 24 hours. The check does not block the current task, and an update still requires confirmation.

Every skill release must also bump the semantic version in its `references/release.json`.

## Hello

Use it for:

- Building a personal context baseline through phased interviews.
- Staging durable personal experiences and real-life changes discovered in ordinary conversations.
- Reviewing candidates and updating a traceable personal context profile.
- Generating the minimum necessary background for a new AI or a specific task.

Candidates go only to a pending area by default. They cannot enter the authoritative profile without item-by-item review and confirmation.

Example:

```text
Use $hello to build my personal context profile through an ongoing interview.
```

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

## Visual Cognitive Learning

Use it for:

- Turning SOPs, business processes, state machines, and solution formation into guided learning models.
- Showing how a complex subject evolved from a simple starting point into its current form.
- Making formula parameters, causal propagation, physical mechanisms, and layered relationships observable and operable.
- Guiding readers from one local question at a time to a final view of the whole relationship.

The input should already be a clear source document. The output is one HTML file that opens offline. Interaction is added only when it improves understanding, and the skill does not invent facts or mechanisms missing from the source.

Example:

```text
Use $visual-cognitive-learning to turn this software development SOP into an offline single-file HTML that teaches the flow step by step and reveals the whole process at the end.
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

- Creating a platform-neutral longform base article from one content kernel.
- Creating standard WeChat articles or standalone Zhihu articles.
- Generating shared body infographics and platform covers according to the visual task.
- Handing an accepted publishing package to the official Wechatsync adapter after explicit authorization.

It preserves facts, viewpoints, conditions, and uncertainty. By default, it does not connect accounts, save drafts, or publish anything.

Visual work conditionally depends on Anthropic's `frontend-design` and `canvas-design`: the former handles precise structured and text-led infographics, while the latter handles conceptual visuals and platform covers. Use `imagegen` only when the chosen direction needs realistic or complex bitmap assets.

Example:

```text
Use $broadcast to turn this content into a complete longform base article, a standard WeChat article, and a standalone Zhihu article.
```

## License

[MIT](./LICENSE)
