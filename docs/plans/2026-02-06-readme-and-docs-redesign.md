# README & Documentation Redesign

**Date:** 2026-02-06
**Status:** Approved

## Problem

The current README.md is overloaded with technical details (internal architecture, optional tool installation instructions, agent/skill descriptions). It should be a simple, readable entry point to the marketplace. Detailed documentation should live separately.

## Design

### New README.md

A short, catalog-style README (~40 lines):

- Project name and one-line description
- Installation one-liner
- Table of available plugins (name + one sentence description), each linking to its docs page
- Links to documentation and contributing guide
- Support and license

No internal architecture details, no optional tool installation, no agent/skill descriptions.

### Documentation Structure

```
docs/
├── README.md                    # Navigation index with links
├── installation.md              # Detailed installation + prerequisites + optional tools
├── plugins/
│   ├── code-review.md           # Practical guide: what it does, commands, examples
│   ├── commit.md                # Practical guide
│   └── python-developer.md      # Practical guide
└── contributing.md              # Plugin architecture, how to create plugins, code standards
```

### Page Content

**docs/README.md** - Link list with one-sentence descriptions. Sections: Getting Started, Plugin Guides, Contributing.

**docs/installation.md** - Three parts:
1. Quick start - one-liner install + verification
2. Prerequisites - Claude Code CLI, Git (required)
3. Optional tools - table of all tools (Semgrep, TruffleHog, Bandit, ruff, mypy, eslint, tsc, prettier, govulncheck) with name, purpose, install command. Note that plugins work without them but provide deeper analysis with them.

**docs/plugins/code-review.md** - Four parts:
1. Overview - one sentence
2. Commands - `/review`, `/review "focus"`, `/fix`, `/analyze-feedback` with examples
3. What it analyzes - bullet list: security, architecture, code quality, secrets, dependencies, standards
4. Optional tools - link to `installation.md#optional-tools`

**docs/plugins/commit.md** - Analogous structure adapted to commit plugin.

**docs/plugins/python-developer.md** - Analogous structure adapted to python-developer plugin.

**docs/contributing.md** - Three parts:
1. Plugin architecture - structure (plugin.json, commands/, agents/, skills/), how they interact
2. Creating a new plugin - step by step
3. Code standards - conventions, testing

### Key Decisions

- Language: English
- Plugin docs are practical (usage-focused), no internal architecture
- Architecture details live in contributing.md only
- Optional tools documentation moves from README to installation.md
- Each plugin doc follows the same structure for consistency
