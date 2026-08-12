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
| [Eagle Eye](./eagle-eye/SKILL.md) | Find and verify timely AI topics for a target audience, with evidence-backed original angles. |
| [Lightning](./lightning/SKILL.md) | Reshape internal documents for fast human reading and clear AI action without losing critical information. |
| [Architecture](./architecture/SKILL.md) | Turn confirmed architecture facts into a trustworthy, clear, offline single-file HTML architecture diagram. |
| [Visual Cognitive Learning](./visual-cognitive-learning/SKILL.md) | Translate a clear source document into a guided, offline single-file HTML learning model that ends with the whole picture. |
| [Writing Style](./writing-style/SKILL.md) | Extract, manage, select, and apply a stable, recognizable writing voice. |
| [Broadcast](./broadcast/SKILL.md) | Engineer headlines, covers, openings, bodies, and endings separately, then turn a complete internal source into four platform-native articles. |
| [Distribution](./distribution/SKILL.md) | Deliver accepted articles, verify the final state, and register channel objects and public URLs. |
| [Skill Release Auditor](./skill-release-auditor/SKILL.md) | Verify a published skill's remote source, structure, release consistency, isolated installation, Codex discovery, and trigger boundaries. |

## Installation

Ask an agent that supports `SKILL.md` to install:

```text
Install this skill:
https://github.com/bryce-code-world/skills/tree/main/lightning
```

You can also copy the `lightning` directory into your local skills directory.

For Hello, replace the link or directory name with `hello`.

For Eagle Eye, replace the link or directory name with `eagle-eye`.

For Architecture, replace the link or directory name with `architecture`.

For Visual Cognitive Learning, replace the link or directory name with `visual-cognitive-learning`.

For Writing Style, replace the link or directory name with `writing-style`.

For Broadcast, replace the link or directory name with `broadcast`.

For Distribution, replace the link or directory name with `distribution`.

For Skill Release Auditor, replace the link or directory name with `skill-release-auditor`.

The nine skills install independently. Business skills do not install missing capabilities while running; add or update skills through the source repository, a plugin, or an explicit user-requested installation flow.

Architecture automatically installs only the allowlisted dependencies declared in its `dependencies.md`, and only when the current task needs them. Unknown or changed sources, unverifiable versions, and dependency updates are never installed automatically.

Broadcast, Writing Style, and Distribution do not perform 24-hour update checks at runtime.

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

## Eagle Eye

Use it for:

- Finding recent AI events that deserve a target audience's attention.
- Loading the AI direction first, then querying shared research, patent, open-source, policy, company, people, and public-attention sources.
- Clustering duplicate coverage and verifying original sources.
- Separating current attention from emerging attention potential.
- Using a target-audience attention model instead of a single public-heat score.
- Comparing the write-worthiness of candidate events.
- Developing an evidence-backed angle that adds reader value.
- Checking existing coverage, counter-evidence, and topic expiry online.
- Using healthy Agent Reach channels as an optional acquisition layer when already installed.

Eagle Eye currently includes the AI direction. Direction configuration, the global shared source catalog, and five target-audience attention profiles are maintained separately. Eagle Eye reads sources without owning their long-term maintenance. Topic cards are written first for the person choosing what to write: even when the eventual article targets specialists, someone new to the subject should understand in one pass what happened, who it affects, and what question is worth writing about. It stops at verified topics and does not continue into internal or public article writing. Research does not start and files are not created until the user confirms the delivery directory. Each run collects up to three topics in one dated file, and reruns for the same topic on the same day replace that day's file.

Example:

```text
Use $eagle-eye to find up to three AI topics from the last seven days that are worth writing about for AI developers, each with an original angle, and explain them in plain language in today's file under a directory I confirm.
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

- Declaring the audience cognition level before writing, then separating recognizable terms from shared concepts and concepts that still need explanation.
- Using simple shared language for general audiences, establishing meaning before introducing necessary technical terms.
- Engineering the title, cover, opening, body, and ending separately, then having an independent reader run all five gates plus an unseen transfer task.
- Creating standard WeChat articles, standalone Zhihu articles, CSDN technical articles, or Juejin technical articles.
- Having every platform read the same internal source and concise broadcast brief directly, never another platform draft.
- Applying a developer-content eligibility gate before generating CSDN or Juejin versions.
- Keeping only necessary, sanitized code blocks with environment and result context in CSDN and Juejin articles.
- Keeping WeChat personal and directory-free by default, strengthening reasoning on Zhihu, technical closure on CSDN, and engineering trade-offs on Juejin.
- Applying a restrained editorial visual system and handing real-draft layout criteria to Distribution for verification.
- Generating a title-aligned entry cover for each platform and shared body infographics only when they improve understanding.
- Handing accepted release packages to `$distribution` when delivery is explicitly requested, without managing accounts, browsers, or publication state inside Broadcast.

It preserves facts, viewpoints, conditions, and uncertainty. By default, it does not connect accounts, save drafts, or publish anything.

Use `canvas-design` when conceptual visuals or platform covers need it, and `imagegen` only when an established direction requires realistic or complex bitmap assets. Prefer native editable graphics for precise infographics instead of introducing another skill.

Example:

```text
Use $broadcast to derive the audience gap and target effect from this complete internal source, calibrate the headline, cover, opening, body, and ending as separate communication jobs, then create platform-native WeChat, Zhihu, CSDN, and Juejin articles.
```

## Distribution

Use it for:

- Checking the target platform, account, accepted article, assets, and current authorization.
- Prefilling or saving accepted WeChat, Zhihu, CSDN, and Juejin articles as drafts.
- Publishing only after explicit authorization and verifying the result from the draft list or public page.
- Distinguishing filled, draft-saved, draft-verified, published, and publish-verified states.
- Maintaining channel objects and canonical public URLs in the article package for later data tracking.
- Loading only the selected channel module while keeping authorization and state handling shared.

Distribution does not rewrite content or automatically install browser tools, MCP servers, plugins, or runtimes. When browser control is unavailable, it preserves the local release package for manual delivery.

Example:

```text
Use $distribution to save this accepted WeChat release package to the specified account's draft box, reopen it to verify the title, body, cover, and mobile layout, and do not publish it.
```

## Skill Release Auditor

Use it for:

- Checking whether a single-skill or multi-skill GitHub repository is fully published.
- Pinning a branch or tag to a commit before validating structure and version consistency.
- Testing direct retrieval or `npx skills add` inside an operating-system temporary directory.
- Separating files on disk from real Codex discovery and trigger behavior.
- Reporting failures, blockers, skipped checks, and temporary-resource cleanup accurately.

The auditor provides native Windows PowerShell 5.1+ and macOS POSIX `sh` scripts without requiring Python.

If strict YAML parsing is unavailable, it requests permission before downloading a pinned `yq`. It verifies the hash and removes the temporary tool after the check.

By default, it reports in the current conversation. It neither creates a report file nor modifies or republishes the checked skill.

Example:

```text
Use $skill-release-auditor to check this GitHub skill release and report all six layers plus anything that remains unverified.
```

## License

[MIT](./LICENSE)
