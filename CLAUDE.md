@AGENTS.md

## Claude Code Additions

- `AGENTS.md` (imported above) is the single source of truth for repository conventions, the plan/approve/implement/validate workflow, and validation policy. Read it in full before making changes.
- The skills it references (`plan-pipeline-change`, `implement-nfcore-nextflow`, `validate-hlarnaseq`) live in `.agents/skills/` and are exposed to Claude Code via a symlink at `.claude/skills/`. They are also wired up as dedicated subagents in `.claude/agents/` (`planner`, `coder`, `validator`) that mirror the Codex roles in `.codex/config.toml`.
- This applies whether or not work is delegated to those subagents: for any pipeline change, default to the plan → approve → implement → validate cycle (invoking the `planner`/`coder`/`validator` subagents, or the equivalent skills directly, is the normal way to do this). Only skip the plan/approval stop when the human explicitly says to make the change directly for this request — see AGENTS.md § "Bypassing the plan/approve cycle" for the bar that language has to clear. Changes scoped to `AGENTS.md`, `.agents/**`, `.claude/**`, or `artifacts/ai-*.md` are AI-configuration maintenance and are exempt by default (see AGENTS.md § "AI Configuration Maintenance").
- Ignore the Codex-specific escalation syntax in `AGENTS.md` (`sandbox_permissions="require_escalated"`). Claude Code handles permission escalation through its own prompt/allowlist flow — see `.claude/settings.json`.
