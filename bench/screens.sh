#!/usr/bin/env bash
# Prints the panels used in the write-up, one per screenshot.
# Usage: bench/screens.sh [1-6]   (no argument prints all)
b=$'\033[1m'; d=$'\033[2m'; g=$'\033[32m'; y=$'\033[33m'; r=$'\033[0m'

p1() {
cat <<T

  ${b}STARTUP OVERHEAD${r}   ${d}prompt tokens before the session does anything${r}

    ${g}sh${r}           ${b}    895${r}   one shell tool
    ${g}sh-read${r}      ${b}  1,503${r}   + native file reader
    ${g}read-edit${r}    ${b}  2,087${r}   + Read, Edit, Write
    restricted     11,612   everything that can't execute code
    ${y}default${r}      ${b} 17,625${r}   stock Claude Code

  ${d}Claude Code v2.1.278 · Opus 5 low effort · bench/run.sh --tasks hello${r}
T
}

p2() {
cat <<T

  ${b}SAME TASK, BOTH PRESETS${r}   ${d}3 runs each, live TypeScript repo${r}

    task      preset      cost      turns    prompt tokens
    ────────────────────────────────────────────────────────
    inspect   ${g}sh${r}        ${g}\$0.0667${r}     4.33          12,772
    inspect   ${y}default${r}    \$0.1203     3.67          76,275
    trace     ${g}sh${r}        ${g}\$0.0565${r}     4.33          10,561
    trace     ${y}default${r}    \$0.1174     5.33         103,535

  ${b}~2x cheaper. Same answers.${r}  All 6 trace runs found src/config.ts:176.
  ${d}The most complete answer came from the cut preset.${r}
T
}

p3() {
cat <<T

  ${b}AFTER COMPACTION${r}   ${d}what the session costs at the start of every cycle${r}

    ${g}sh${r}         13,440  →  21,532  →   8,416          ${b}floor ~14k${r}
    ${y}default${r}    35,628  →  32,190  →  37,476  →  38,082  →  36,363
                                                     ${b}floor ~36k${r}

    ${d}100k window, minus a ~35k reserve = ~65k trigger${r}

    room to actually work in:   ${g}sh ~51k${r}   vs   ${y}default ~27k${r}

  ${b}Paid again after every single compaction.${r}
T
}

p4() {
cat <<T

  ${b}WORK DONE BETWEEN COMPACTIONS${r}   ${d}tool calls per cycle${r}

    ${g}sh${r}         12  →  12  →  ${b}15${r}  →  ${b}20${r}        ${g}going up${r}

    ${y}default${r}    14  →  13  →  11  →  9  →  9  →  ${b}6${r}    ${y}going down${r}

  ${d}Less room per cycle means less work per cycle.${r}
T
}

p5() {
cat <<T

  ${b}DOES CUTTING SURVIVE COMPACTION?${r}

    before any compaction    ${g}mcp__sh__sh${r} ×12
    after compaction 1       ${g}mcp__sh__sh${r} ×12
    after compaction 2       ${g}mcp__sh__sh${r} ×15
    after compaction 3       ${g}mcp__sh__sh${r} ×20

    ${b}Zero stock tools. Ever.${r}

  ${y}What DOES bring them back:${r}
    claude --continue        ${d}← flags live in the command line${r}
    claude attach <id>       ${d}← not in the session${r}
T
}

p6() {
cat <<T

  ${b}THE ONE KNOB YOU SHOULD NOT TOUCH${r}

    tool search ${g}ON${r}  (default)      17,026 / 18,586 tokens
    ENABLE_TOOL_SEARCH=${y}false${r}       36,345 / 39,403 tokens

    ${b}Turning it off doubles your context.${r}

  ${d}Claude Code ships tool NAMES and loads schemas on demand.${r}
  ${d}Some proxy setups disable this. Check your alias.${r}
T
}

case "${1:-all}" in
  1) p1 ;; 2) p2 ;; 3) p3 ;; 4) p4 ;; 5) p5 ;; 6) p6 ;;
  all) p1; p2; p3; p4; p5; p6 ;;
esac
echo
