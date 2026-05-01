# Worked examples of project-specific rules

The shared `CLAUDE.md` covers behavior that applies to any project: don't hedge, don't waffle, don't delegate to the user, don't promise fake futures. But most real projects also need project-specific rules — facts the AI should never re-derive, deployment particularities, environment constraints. Append these below the *"Append project-specific rules below this line"* marker in `CLAUDE.md`.

Two examples follow. They were extracted from a real project (a trading bot deployed on AWS); use them as templates.

---

## Example 1 — Project facts the AI keeps re-deriving wrong

If your AI keeps making up the same wrong assumption every session — about fees, API behavior, environment defaults — write the truth down once and tell it to stop re-deriving. Frame it bluntly so the AI knows the assumption has been corrected before.

```markdown
## Project facts (do not re-assume; these have been corrected repeatedly)

Claude keeps re-introducing the wrong assumptions about this bot's economics. Stop. These are settled.

- **Gas fees: zero.** This bot trades through a Polymarket proxy wallet — the Polymarket relayer sponsors all order gas. Never include gas in cost, profitability, or sizing math.
- **Merge / redeem fees: zero.** Merging complete sets back to USDC has no fee. Same for redeeming winning positions. Do not model a merge fee anywhere.
- **Trading fees: per-market, taker-only when present.** When a market has fees, they apply to the taker side of a fill; the maker may earn a rebate. Both rates are market-specific and must be read from the live market config in the context of the specific market(s) involved. Do not assume a default fee or a default rebate. Default to zero only when explicitly verified for that market.
```

The pattern is: each fact starts with the conclusion in bold (`Gas fees: zero.`), then a short explanation of why, then an explicit instruction about how to act on it. No hedging, no maybes — these are facts.

---

## Example 2 — Deployment / environment constraints

If the project's actual runtime is somewhere other than the local working directory, write down where it is, how to reach it, and what counts as "done." This stops the AI from declaring victory because tests passed locally when the live system is untouched.

```markdown
## Local doesn't exist — AWS is the only environment

There is no local runtime for this bot, and there is no local data. The only place the code runs and the only place runtime state lives is the systemd `observatory` service on the AWS EC2 instance at `/opt/observatory/app` (see [`deploy/RUNBOOK.md`](deploy/RUNBOOK.md)).

**Deploys.** A code change is not "done" until all of the following have happened:

1. The change is committed and pushed to the remote branch the AWS box pulls from.
2. On the AWS instance: `cd /opt/observatory/app && git pull && npm ci && sudo systemctl restart observatory`.
3. The service comes back up cleanly — verified via `systemctl status observatory` and a fresh tail of `/var/log/observatory/observe-live.log` showing the expected startup lines.

Do not declare a change complete because tests passed, because a one-off `tsx` script ran on this machine, or because the diff "looks right." None of those touch the live bot. If you cannot SSH to the instance yourself, hand the user the exact deploy commands and wait for confirmation that the restart succeeded before reporting the work as done.

**Investigation.** When you need to look something up about the bot's actual behavior — a log line, a config value, the state of a position, the database contents, an env var, what fired at 14:32 — go to the AWS instance. Local copies are stale, partial, or fictional. Specifically:

- Logs: `/var/log/observatory/observe-live.log`, `/var/log/observatory/observe-live.err.log`
- Service state: `systemctl status observatory`
- Runtime config: `/opt/observatory/app/.env`, `/opt/observatory/app/observation-config.json`
- Database: `/opt/observatory/app/data/observatory.sqlite`

Files in this working directory are source code, not state. If you find yourself reading from this machine to answer a question about the bot's actual behavior, stop and SSH to the live one instead.
```

The pattern is: explicit list of where things actually live, explicit definition of "done," and an explicit warning that local files are not the source of truth.

---

## How to draft your own project-specific rules

Ask yourself two questions:

1. **What does my AI keep getting wrong about this project?** Write each one as a fact-with-instruction. Lead with the conclusion in bold, follow with the why, end with what to do.
2. **Where does my project actually run, and what counts as the work being done?** Write down the deployment / activation flow as a numbered checklist. Be specific about commands and verification steps.

Keep additions terse. Long rules get skimmed; short ones get followed.

If a project-specific rule has a phrase signature (e.g., "never include gas in cost math" → block any mention of `gas fee` outside of explicit zero-confirmations), you can extend `block-hedging.sh` with a new `RULE_PROJECT_PATTERN` and a corresponding block message. Keep the rule numbering consistent with `CLAUDE.md`.
