# Claude Rulebook + Stop Hook

A portable behavioral rulebook (`CLAUDE.md`) plus a Stop hook that enforces it at the harness level. Targets the most common AI failure modes that text-only instructions don't reliably suppress: hedging, builder-cost framing, delegation back to the user, and fake "I'll do it later" promises.

The rules go into the user's context every session via `CLAUDE.md`. The hook scans the assistant's last message before delivery and blocks responses containing banned phrases, forcing the model to revise. The user only sees the clean, revised version.

---

## Instructions for Claude (the AI installing this)

When the user asks you to install the Claude Rulebook in their project, do the following:

### 1. Copy the four files into the user's project root, preserving structure

| Source | Destination |
|---|---|
| `CLAUDE.md` | `<project-root>/CLAUDE.md` |
| `.claude/settings.json` | `<project-root>/.claude/settings.json` |
| `.claude/hooks/block-hedging.sh` | `<project-root>/.claude/hooks/block-hedging.sh` |

If the user already has a `CLAUDE.md` or a `.claude/settings.json`, **do not overwrite blindly**. Show the user the diff and let them decide how to merge. Common safe merges:
- Their `CLAUDE.md` has project-specific rules → append the rulebook above their rules, or place project rules below the `Append project-specific rules below this line` marker.
- Their `.claude/settings.json` already has hooks → merge the `Stop` hook entry into the existing `hooks` object rather than replacing the file.

### 2. Make the hook executable

```bash
chmod +x .claude/hooks/block-hedging.sh
```

This step does not survive a plain copy from a tarball or an unzipped archive. Without it, Claude Code silently does nothing when it tries to run the hook.

### 3. Verify dependencies

The hook needs `jq` and `perl`. `perl` is preinstalled on macOS and Linux. `jq` is usually preinstalled on Linux; on macOS run `brew install jq` if missing.

```bash
which jq && which perl
```

### 4. Test the hook directly

Pipe a fake Stop event in. The hook should print a `BLOCKED` message to stderr and exit with code 2.

```bash
echo '{"last_assistant_message":"this might work, almost certainly fine","stop_hook_active":false,"hook_event_name":"Stop"}' \
  | ./.claude/hooks/block-hedging.sh
echo "exit=$?"
```

Expected: stderr contains `BLOCKED by CLAUDE.md.` and lists `Rule 2 violations`. Exit code is `2`.

### 5. Inform the user about activation timing

The hook **takes effect in the next Claude Code session**, not the current one. Claude Code locks its hook configuration at session start. Tell the user to restart Claude Code (close and reopen the CLI / VS Code extension / desktop app) to activate enforcement.

### 6. Ask about project-specific rules

The shared `CLAUDE.md` ends with a line: *"Append project-specific rules below this line."* Most projects benefit from additional rules — deployment specifics, project facts that should never be re-derived, environment quirks. Ask the user about their project context and offer to draft project-specific rules in the same shape as `EXAMPLES.md`.

---

## What the hook actually blocks

Five rules are documented in `CLAUDE.md`. The hook enforces four of them via phrase detection:

| Rule | Title | Detectable phrases |
|---|---|---|
| 1 | Quality is the only variable | `~30 min`, `bigger work`, `lots of work`, `estimated`, `~N hours/days/weeks`, etc. |
| 2 | Verify, don't hedge | `maybe`, `might`, `probably`, `almost certainly`, `you should verify`, etc. |
| 4 | You execute — never delegate | `can you run`, `please paste`, `hand the user`, `for you to run`, etc. |
| 5 | Don't promise future action | `I'll come back to`, `I'll revisit later`, `in a follow-up`, etc. |

Rule 3 (Decide, don't present options) is documented but not phrase-enforced — it's about response structure, not specific words.

When the hook fires, the block message identifies which rule(s) the response broke, quotes the rule text, and tells the model what to do instead (verify, commit, execute, or set up a real schedule). The model continues from where it stopped — typically with new tool calls — and produces a clean response.

A loop guard releases blocking after one failed retry (`stop_hook_active=true`) so the model never gets stuck in an infinite block-and-revise cycle.

The hook strips Markdown code formatting (` ``` `, ` ~~~ `, `` ` ``) before scanning, so meta-discussion about banned phrases works as long as the phrases are in code formatting.

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

## Customizing the hook

Add or remove banned phrases by editing the regex patterns at the top of `block-hedging.sh`:

```bash
RULE1_PATTERN='\b(half day of work|...|estimated)\b|~\s*\d+\s*(min|...|weeks)\b'
RULE2_PATTERN='\b(more likely|maybe|might|...)\b|...'
RULE4_PATTERN='\b(can|could|will|would) you (run|...)\b|...'
RULE5_PATTERN='\b(I.?ll|I will) (revisit|...)\b|...'
```

Each pattern is a Perl-compatible regex. After editing, the change takes effect in the next Claude Code session. Test changes the same way as step 4 above before relying on them.

---

## License

MIT
