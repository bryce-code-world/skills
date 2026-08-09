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
| [Architecture](./architecture/SKILL.md) | Turn confirmed architecture facts into a trustworthy, clear, offline single-file HTML architecture diagram. |
| [Visual Cognitive Learning](./visual-cognitive-learning/SKILL.md) | Translate a clear source document into a guided, offline single-file HTML learning model that ends with the whole picture. |
| [Writing Style](./writing-style/SKILL.md) | Extract, manage, select, and apply a stable, recognizable writing voice. |
| [Broadcast](./broadcast/SKILL.md) | Turn a complete internal source into titles, covers, and four platform-native articles through a decodable communication-effects model. |

## Installation

Ask an agent that supports `SKILL.md` to install:

```text
Install this skill:
https://github.com/bryce-code-world/skills/tree/main/lightning
```

You can also copy the `lightning` directory into your local skills directory.

For Hello, replace the link or directory name with `hello`.

For Architecture, replace the link or directory name with `architecture`.

For Visual Cognitive Learning, replace the link or directory name with `visual-cognitive-learning`.

For Writing Style, replace the link or directory name with `writing-style`.

For Broadcast, replace the link or directory name with `broadcast`.

The six skills install independently. Except for Architecture, a skill asks once before installing a missing dependency, and only when the current task actually needs it.

Architecture automatically installs only the allowlisted dependencies declared in its `dependencies.md`, and only when the current task needs them. Unknown or changed sources, unverifiable versions, and dependency updates are never installed automatically.

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

## Architecture

Use it for:

- Enterprise product blueprints, platform capability maps, and business-to-technology architecture diagrams.
- Layered systems, microservices, AI platforms, and data platforms.
- Dense blueprints with cross-cutting sidebars, external dependencies, data planes, or infrastructure layers.
- Interactive architecture models only when progressive exploration, evolution, or path focus improves understanding.

The input should contain confirmed components, groups, relationships, and boundaries. Architecture first builds an internal diagram brief, then routes to the appropriate static layout, visual learning, or frontend design capability while enforcing offline icons, stable canvases, precise connectors, and browser validation.

The output is one HTML file that opens directly through `file://`. Reference images guide visual direction only and never become architecture facts.

Example:

```text
Use $architecture to turn this enterprise AI platform design into a trustworthy, clear, offline single-file HTML architecture diagram.
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

- Deriving the audience's shared understanding, easily misread concepts, key gap, and primary comprehension, judgment, or action outcome from one complete internal source.
- Using simple shared language for general audiences, establishing meaning before introducing necessary technical terms.
- Designing the title, cover, and opening before drafting, then calibrating them against the finished article through entry, fulfillment, and effect gates.
- Creating standard WeChat articles, standalone Zhihu articles, CSDN technical articles, or Juejin technical articles.
- Having every platform read the same internal source and concise broadcast brief directly, never another platform draft.
- Applying a developer-content eligibility gate before generating CSDN or Juejin versions.
- Keeping only necessary, sanitized code blocks with environment and result context in CSDN and Juejin articles.
- Keeping WeChat personal and directory-free by default, strengthening reasoning on Zhihu, technical closure on CSDN, and engineering trade-offs on Juejin.
- Applying a restrained editorial visual system while distinguishing saved drafts, confirmed content, and accepted layout.
- Generating a title-aligned entry cover for each platform and shared body infographics only when they improve understanding.
- Saving and checking accepted drafts through four independent Playwright MCP profiles after explicit authorization, automatically installing and rediscovering the official MCP when missing.

It preserves facts, viewpoints, conditions, and uncertainty. By default, it does not connect accounts, save drafts, or publish anything.

Visual work conditionally depends on Anthropic's `frontend-design` and `canvas-design`: the former handles precise structured and text-led infographics, while the latter handles conceptual visuals and platform covers. Use `imagegen` only when the chosen direction needs realistic or complex bitmap assets.

Example:

```text
Use $broadcast to derive the audience gap and target effect from this complete internal source, then design the title, cover, opening, and platform-native WeChat, Zhihu, CSDN, and Juejin articles.
```

## License

[MIT](./LICENSE)
