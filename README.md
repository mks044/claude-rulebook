# Claude Rulebook + Stop Hook

A portable behavioral rulebook (`CLAUDE.md`) plus a Stop hook that enforces it at the harness level. It targets the AI failure modes that text instructions alone don't reliably suppress: hedging, builder-cost/effort framing, delegating work back to the user, and fake "I'll do it later" promises.

The rules load into context every session. The hook scans the assistant's final message before it reaches you and blocks any response containing banned phrases, forcing a revision. You only ever see the clean version.

---

## Install

Hand this repo to your coding agent. That's the install step.

> Paste this to your Claude Code agent:
>
> **"Install the Claude Rulebook from https://github.com/mks044/claude-rulebook into this project."**

The agent does the rest. The section below is written for the agent, not for you — you don't need to read it.

---

## Instructions for the agent

You are installing this rulebook for the operator. Do the whole thing yourself — don't hand any of it back to them.

1. **Place three files**, preserving structure. Default to the project root; use `~/.claude/` instead if the operator wants it active everywhere (in that case rewrite the hook path in `settings.json` to an absolute path).

   | File | Destination |
   |---|---|
   | `CLAUDE.md` | `<root>/CLAUDE.md` |
   | `.claude/settings.json` | `<root>/.claude/settings.json` |
   | `.claude/hooks/block-hedging.sh` | `<root>/.claude/hooks/block-hedging.sh` |

2. **Don't clobber existing config.** If a `CLAUDE.md` already exists, append these rules above theirs (or below the *"Append project-specific rules"* marker). If `.claude/settings.json` already has hooks, merge the `Stop` entry into the existing `hooks` object — don't replace the file.

3. **`chmod +x .claude/hooks/block-hedging.sh`** — a plain copy drops the executable bit and the hook silently no-ops without it.

4. **Confirm deps and self-test.** The hook needs `jq` and `perl` (both standard on macOS/Linux; `brew install jq` if missing). Verify it fires:
   ```bash
   echo '{"last_assistant_message":"this might work, ~30 min of work","stop_hook_active":false}' \
     | ./.claude/hooks/block-hedging.sh; echo "exit=$?"
   ```
   Expect a `BLOCKED by CLAUDE.md.` message on stderr and `exit=2`.

5. **Tell the operator to restart.** Claude Code locks hooks at session start — enforcement begins next session, not this one.

6. **Offer project rules.** `CLAUDE.md` ends with an *"Append project-specific rules below this line"* marker. Ask about their project (deploy specifics, facts that should never be re-derived, environment quirks) and draft rules in the shape of `EXAMPLES.md`.

---

## What the hook blocks

| Rule | Title | Caught phrases |
|---|---|---|
| 1 | Quality is the only variable | `~30 min`, `bigger work`, `lots of work`, `estimated`, `~N hours/days` |
| 2 | Verify, don't hedge | `maybe`, `might`, `probably`, `almost certainly`, `you should verify` |
| 4 | You execute — never delegate | `can you run`, `please paste`, `hand the user`, `for you to run` |
| 5 | Don't promise future action | `I'll come back to`, `I'll revisit later`, `in a follow-up` |

Rule 3 (Decide, don't present options) is documented but not phrase-enforced — it's about structure, not specific words.

When it fires, the block message names the broken rule, quotes it, and tells the model what to do instead. A loop guard releases after one failed retry (`stop_hook_active=true`) so it never gets stuck. It strips Markdown code formatting before scanning, so meta-discussion about banned phrases works as long as they're wrapped in backticks.

To customize, edit the `RULE*_PATTERN` regexes at the top of `block-hedging.sh`. Changes take effect next session.

---

## Files

| File | Purpose |
|---|---|
| `CLAUDE.md` | Portable behavioral rulebook (5 rules + banner) |
| `.claude/settings.json` | Registers the Stop hook |
| `.claude/hooks/block-hedging.sh` | Enforcement script (Bash + Perl + jq) |
| `EXAMPLES.md` | Worked examples of project-specific rules to append |
| `LICENSE` | MIT |

---

## License

MIT
