# Claude Code

`home/.claude/` installs to `~/.claude/`, so every project on the machine gets the same behavior.

```
home/.claude/
├── CLAUDE.md     # global rules: short answers, diagrams over prose, plain voice, I decide
└── skills/       # loaded on demand, by name or when the task matches
```

`scripts/install.sh` copies both. Skills you add to `~/.claude/skills/` yourself are left alone. `scripts/sync-from-system.sh` copies your edits back.

## Skills

All are vendored unchanged from their upstream (minus Codex-only `agents/` folders), with the upstream license in each folder. `technical-writing`, `write-report` and `code-quality` are the exceptions: they're my own (from asusoda/platform, arc-lab, and sparky plus piramid), made project-neutral.

| Skill | What it's for | Source | License |
|---|---|---|---|
| `frontend-design` | Visual direction that doesn't look templated | [anthropics/skills](https://github.com/anthropics/skills) | Apache-2.0 |
| `emil-design-eng` | UI polish, component and motion details | [emilkowalski/skills](https://github.com/emilkowalski/skills) | MIT |
| `better-interface` | One ranked review across all the areas below | [jakubkrehel/skills](https://github.com/jakubkrehel/skills) | MIT |
| `better-ui` | Surfaces, radii, shadows, icons, motion values | jakubkrehel/skills | MIT |
| `better-typography` | Type scale, spacing, wrapping, font features | jakubkrehel/skills | MIT |
| `better-colors` | Palettes, semantic tokens, contrast | jakubkrehel/skills | MIT |
| `better-layout` | Grouping, alignment, responsive structure | jakubkrehel/skills | MIT |
| `better-writing` | Interface copy: labels, errors, empty states | jakubkrehel/skills | MIT |
| `better-accessibility` | Keyboard, focus, ARIA, WCAG 2.2 | jakubkrehel/skills | MIT |
| `interface-review` | Interface problems a diff or PR introduced | jakubkrehel/skills | MIT |
| `technical-writing` | Docs and comments in Simplified Technical English | this repo | MIT |
| `write-report` | Honest results write-ups: every number and citation sourced, measured vs suggested | this repo | MIT |
| `unslop` | Remove AI tells from a draft (run with `/unslop`) | [cursor/plugins](https://github.com/cursor/plugins) | MIT |
| `writing-for-agents` | Writing skills, CLAUDE.md and AGENTS.md | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT |
| `pr` | PR body: a diagram of the change, before/after evidence (screenshots first), merge risk | mattpocock/skills | MIT |
| `show-me` | Explain the current topic visually (run with `/show-me`) | [humanlayer/skills](https://github.com/humanlayer/skills) | MIT |
| `mermaid-diagrams` | Mermaid that renders | [ccheney/robust-skills](https://github.com/ccheney/robust-skills) | MIT |
| `grilling` | Stress-test a plan, one round of questions at a time | mattpocock/skills | MIT |
| `discernment-nudge` | 2-3 follow-up questions after advice you'll act on | anthropics/skills | Apache-2.0 |
| `karpathy-guidelines` | Karpathy's LLM coding pitfalls: assumptions, simplicity, surgical diffs, verifiable goals | [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | MIT |
| `code-quality` | Naming, file and folder layout, modular-monolith boundaries, reuse, removing dead code and silent fallbacks | this repo | MIT |
| `codebase-design` | Deep modules: where seams go, small interfaces over big ones | mattpocock/skills | MIT |
| `receiving-code-review` | Verify review feedback, then agree or push back with reasons | obra/superpowers | MIT |
| `systematic-debugging` | Root cause before fixes | [obra/superpowers](https://github.com/obra/superpowers) | MIT |
| `verification-before-completion` | Evidence before saying "done" | obra/superpowers | MIT |

## Not included, worth a look

- [pbakaus/impeccable](https://github.com/pbakaus/impeccable) and [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill): bigger design skills with their own scripts and browser checks. Install them from upstream if you want them, since they update often.
- [HiP1/Satori](https://github.com/HiP1/Satori): a long anti-sycophancy framework (CC BY 4.0). The calibration rules in `CLAUDE.md` cover the same ground in six lines.
- [blader/humanizer](https://github.com/blader/humanizer): a longer version of `unslop`.

## Updating a skill

Copy the folder from upstream over the one in `home/.claude/skills/`, check `git diff`, and commit.
