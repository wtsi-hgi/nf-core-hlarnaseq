@AGENTS.md

## Claude Code Additions

- `AGENTS.md` (imported above) is the single source of truth for repository conventions, the plan/approve/implement/validate workflow, and validation policy. Read it in full before making changes.
- The skills it references (`plan-pipeline-change`, `implement-nfcore-nextflow`, `validate-hlarnaseq`) live in `.agents/skills/` and are exposed to Claude Code via a symlink at `.claude/skills/`. They are also wired up as dedicated subagents in `.claude/agents/` (`planner`, `coder`, `validator`) that mirror the Codex roles in `.codex/config.toml`.
- Ignore the Codex-specific escalation syntax in `AGENTS.md` (`sandbox_permissions="require_escalated"`). Claude Code handles permission escalation through its own prompt/allowlist flow — see `.claude/settings.json`.
