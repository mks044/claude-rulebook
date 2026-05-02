#!/usr/bin/env bash
# Stop hook: blocks assistant responses that violate enforcement rules in CLAUDE.md.
#
# Currently enforces four rule families:
#   Rule 1 — Quality is the only variable:   bans builder-cost / effort-framing phrases
#   Rule 2 — Verify, don't hedge:            bans hedging phrases
#   Rule 4 — You execute, never delegate:    bans delegation-to-user phrases
#   Rule 5 — Don't promise future action:    bans deferral promises with no mechanism
#
# When a violation fires, exits 2 and writes a rule-specific block message to
# stderr. Claude Code feeds stderr back into the model so the next turn knows
# which rule it broke and what corrective behavior is expected.
#
# Loop guard: if the hook has already fired once in this turn
# (stop_hook_active=true) and the model is still violating, the hook lets the
# response through. Prevents infinite block/regenerate loops.

set -euo pipefail

INPUT=$(cat)
MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')

if [ -z "$MSG" ]; then
    exit 0
fi

# --- Rule 2 patterns: hedging language ------------------------------------
RULE2_PATTERN='\b(more likely|most plausibly|plausibly|maybe|might|potentially|perhaps|presumably|likely|probably|almost certainly|almost always|fairly certain|could be|seems to|appears to|I think|I believe)\b|you may want to check|you should verify|I.?d recommend confirming|\bI (can.?t|cannot|can not) (verify|confirm|check|tell|determine|be sure)\b|\b(unable|not able) to (verify|confirm|check|tell|determine|be sure)\b|\bno way (to|for me to) (verify|confirm|check|tell|determine|be sure)\b|\bcannot be (verified|confirmed|checked|determined)\b|\bI (haven.?t|have not) (ruled out|measured|checked|verified|tested|confirmed|determined|investigated|looked|looked at|looked into|researched)\b|\bI (don.?t|do not) know\b|\bneed to (confirm|verify|check|validate)\b'

# --- Rule 1 patterns: builder-cost / effort framing -----------------------
RULE1_PATTERN='\b(half day of work|half a day of work|half day|day of work|days of work|hours of work|minutes of work|bigger work|more work|lot of work|lots of work|more effort|lot of effort|lots of effort|estimated)\b|~\s*\d+\s*(min|mins|minute|minutes|hr|hrs|hour|hours|day|days|week|weeks)\b|\b(ranked|sorted|ordered|prioritized|grouped) by (effort|complexity|difficulty)\b'

# --- Rule 4 patterns: delegation-to-user -----------------------------------
RULE4_PATTERN='\b(can|could|will|would) you (run|paste|grep|search|fetch|verify|check)\b|\bplease (run|paste|grep|search|fetch|verify|check)\b|\bI need you to (run|check|paste|grep|search|verify|provide|share|test|try|do|fix)\b|\bI.?d need you to (run|check|paste|grep|search|verify|provide|share|test|try|do|fix)\b|\bif you could (run|paste|grep|search|fetch|verify|check)\b|\bhand (you|the user|them)\b|\bso (you|they|the user) can( either| also| even| just| now| then)? (run|pull|execute|deploy|paste|grep|fetch|scp|copy|cat|tail)\b|\bfor (you|them|the user) to (run|execute|deploy|paste|grep|pull|scp|copy)\b|\b(I.?ll|I will) (give|hand|provide|prepare) (you|the user|them) (the |a |concrete |some )?(command|commands|script|steps|instructions)\b'

# --- Rule 5 patterns: fake-future-promise (deferral without mechanism) -----
RULE5_PATTERN='\b(I.?ll|I will) (revisit|come back to|loop back|circle back|get back to|tackle (this|that|it|them|those) later)\b|\b(I.?ll|I will) \w+\b.{0,60}\b(later|in a follow.?up|down the road|next round|next iteration|subsequently|eventually)\b|\bin a follow.?up\b'

# Strip Markdown code formatting before matching so the hook can coexist with
# meta-discussion about itself (a phrase wrapped in backticks or fenced code
# blocks is a string for reference, not a natural-language claim).
strip_code_formatting() {
    perl -0777 -pe 's/```[\s\S]*?```//g; s/~~~[\s\S]*?~~~//g; s/`[^`]*`//g'
}

extract_matches() {
    printf '%s' "$MSG" \
        | strip_code_formatting \
        | perl -ne 'while (/'"$1"'/gi) { print "$&\n" }' \
        | awk '!seen[tolower($0)]++' \
        | head -10
}

format_list() {
    printf '%s' "$1" | paste -sd ',' - | sed 's/,/, /g'
}

RULE1_HITS=$(extract_matches "$RULE1_PATTERN")
RULE2_HITS=$(extract_matches "$RULE2_PATTERN")
RULE4_HITS=$(extract_matches "$RULE4_PATTERN")
RULE5_HITS=$(extract_matches "$RULE5_PATTERN")

if [ -z "$RULE1_HITS" ] && [ -z "$RULE2_HITS" ] && [ -z "$RULE4_HITS" ] && [ -z "$RULE5_HITS" ]; then
    exit 0
fi

if [ "$STOP_ACTIVE" = "true" ]; then
    exit 0
fi

{
    echo "BLOCKED by CLAUDE.md."
    echo

    if [ -n "$RULE1_HITS" ]; then
        echo "Rule 1 violations (Quality is the only variable): $(format_list "$RULE1_HITS")"
        echo
        echo "Rule 1 (CLAUDE.md, project root):"
        echo "\"Builder cost is fictional. There is no human engineer, no team, no sprint, no budget, no fatigue, no token limit — the AI is the only builder. Effort, time, and lines of code are not real variables. Do not factor them into reasoning, do not mention them, do not trade them off against anything.\""
        echo
        echo "What this means: you used effort/size language to frame a decision. There is no engineer who has to do the work. There is no time pressure. The amount of work is not a real variable in this project. Do not scope the answer smaller because the alternative would be 'more work' or 'bigger work' — pick the highest-quality answer regardless of how much code, research, or investigation it requires, and execute it. Reread Rule 1 in CLAUDE.md and revise your response so the chosen path is justified by quality alone, not by effort."
        echo
    fi

    if [ -n "$RULE2_HITS" ]; then
        echo "Rule 2 violations (Verify, don't hedge): $(format_list "$RULE2_HITS")"
        echo
        echo "Rule 2 (CLAUDE.md, project root):"
        echo "\"Hedging language [...] means the work is unfinished. Before answering, read the code, run the command, check the logs, fetch the docs. Never push verification back to the user when you can do it yourself. When a fact is unknown, the next action is to go find it — not to ask the user, and not to deliver a partial answer with caveats. Only deliver the answer once it is verified.\""
        echo
        echo "What this means: you presented information you were not sure about. You hedged instead of verifying. Go investigate the underlying fact — read the code, run the command, fetch the docs, check the logs — and rewrite your response with verified claims only. If something genuinely cannot be verified after real investigation, say so plainly; do not paper over uncertainty with soft language."
        echo
    fi

    if [ -n "$RULE4_HITS" ]; then
        echo "Rule 4 violations (You execute — never delegate to the user): $(format_list "$RULE4_HITS")"
        echo
        echo "Rule 4 (CLAUDE.md, project root):"
        echo "\"You have full tool access in this environment: Bash, file reads, file writes, network fetches, MCP servers, and whatever credentials are configured for this machine. The user is not your hands. Phrases like 'can you run X', 'please paste Y', 'could you check Z' [...] are hallucinations of limited access — the real problem is that you have not looked deeply enough at the tools, paths, and credentials available to you.\""
        echo
        echo "What this means: you tried to push execution onto the user. The user does not run commands; you do. You have Bash, Read, Write, network access, and whatever credentials are configured in this environment. Before delegating anything, exhaust your tool access — try running it yourself, check the relevant paths and env vars, SSH to the remote machine if needed. The default assumption is that you can do the action — you have just not looked hard enough at the tools available. Only after a real, multi-step investigation may you state a specific tool gap, and even then name the exact limit (e.g., 'the server is unreachable from this network') instead of pushing the action onto the user."
        echo
    fi

    if [ -n "$RULE5_HITS" ]; then
        echo "Rule 5 violations (Don't promise future action without a mechanism): $(format_list "$RULE5_HITS")"
        echo
        echo "Rule 5 (CLAUDE.md, project root):"
        echo "\"You have no 'later.' Once this turn ends, you do not autonomously come back unless the user re-prompts or you have actually invoked a real scheduling mechanism (/schedule for cron routines, ScheduleWakeup for self-paced /loop re-entry). Phrases like 'I'll schedule that', 'I'll come back to it', 'I'll revisit this later', 'I'll handle that in a follow-up', 'I'll fix it next round' are fake commitments — no enforcement, no execution path. The user keeps thinking the work is happening; it isn't.\""
        echo
        echo "What this means: you promised to do something later without any mechanism to actually do it later. That is a lie. There is no 'later' for you — the turn ends, you stop, and unless the user re-prompts or you have set up a real scheduled agent, the promised work never happens. Pick one of these and do it now: (a) actually do the work in this turn, (b) invoke /schedule to set a real future agent that will do the work, (c) invoke ScheduleWakeup if you are inside a /loop, or (d) state plainly that the task is incomplete and the user must re-prompt to continue. Remove the deferral promise from your response."
        echo
    fi

    echo "Revise: do not just delete the banned words — fix the underlying behavior they signal (verify what was hedged; commit to the right answer regardless of effort; execute the action yourself instead of asking the user; do the work now or set up a real mechanism instead of fake-promising it for later)."
} >&2

exit 2
