#!/bin/zsh
# Claude Code status line — multi-line footer.
#
# Line 1: model + effort, context-remaining bar/%, session cost + time.
# Line 2: cwd, project dir (if different), git branch + working-tree status.
# Line 3: plugins / skills / agents / hooks / MCP servers currently available.
#
# stdin: session JSON from Claude Code.
#   docs: https://code.claude.com/docs/en/statusline#available-data
# Line 1's cost/time/context come straight from that JSON. Line 3's counts are
# NOT in the JSON — they are derived by reading local config files, so they are
# a best-effort reflection of Claude Code's internal view (see notes by each
# section). Output is plain text with ANSI color; Claude Code renders each
# printed line as its own row.

emulate -L zsh
setopt no_nomatch          # a glob that matches nothing expands to nothing

input=$(cat)
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Read one field from the session JSON on stdin.
jqr() { print -r -- "$input" | jq -r "$1" 2>/dev/null }

# --- ANSI colors ------------------------------------------------------------
RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; BLUE=$'\033[34m'; GREY=$'\033[38;5;245m'
GREEN=$'\033[32m'; ORANGE=$'\033[38;5;208m'; RED=$'\033[31m'
DARKRED=$'\033[38;5;88m'; BLACK=$'\033[30m'; YELLOW=$'\033[33m'

# ============================================================================
# LINE 1 — model, effort, context window, cost, time
# ============================================================================
MODEL=$(jqr '.model.display_name')
EFFORT=$(jqr '.effort.level // empty')
COST=$(jqr '.cost.total_cost_usd // 0')
DUR_MS=$(jqr '.cost.total_duration_ms // 0'); DUR_MS=${DUR_MS%%.*}
REMAIN=$(jqr '.context_window.remaining_percentage // empty')
USED=$(jqr '.context_window.used_percentage // empty')

# % of context window still AVAILABLE. Prefer the field; else derive from used;
# else (no context data yet, e.g. before the first response) treat as full.
if [[ -n "$REMAIN" ]]; then
  REMAIN_INT=${REMAIN%%.*}
elif [[ -n "$USED" ]]; then
  REMAIN_INT=$(( 100 - ${USED%%.*} ))
else
  REMAIN_INT=100
fi
[[ -z "$REMAIN_INT" || "$REMAIN_INT" != <-> ]] && REMAIN_INT=100
(( REMAIN_INT < 0 )) && REMAIN_INT=0
(( REMAIN_INT > 100 )) && REMAIN_INT=100

# Color bands by % AVAILABLE.
if   (( REMAIN_INT >= 80 )); then CTX_COLOR=$GREEN
elif (( REMAIN_INT >= 50 )); then CTX_COLOR=$ORANGE
elif (( REMAIN_INT >= 20 )); then CTX_COLOR=$RED
elif (( REMAIN_INT >= 1  )); then CTX_COLOR=$DARKRED
else                              CTX_COLOR=$BLACK
fi

# 10-cell bar: filled cells = remaining context.
FILLED=$(( REMAIN_INT / 10 ))
(( FILLED < 0 )) && FILLED=0
(( FILLED > 10 )) && FILLED=10
BAR=""
for (( i = 0; i < 10; i++ )); do
  if (( i < FILLED )); then BAR+="█"; else BAR+="░"; fi
done

MINS=$(( DUR_MS / 60000 )); SECS=$(( (DUR_MS % 60000) / 1000 ))
COST_FMT=$(printf '$%.2f' "$COST" 2>/dev/null || print -n '$0.00')

EFFORT_STR=""
[[ -n "$EFFORT" ]] && EFFORT_STR=" ${DIM}·${RESET} ${YELLOW}${EFFORT}${RESET}"

LINE1="${CYAN}${BOLD}${MODEL}${RESET}${EFFORT_STR}   ${CTX_COLOR}${BAR} ${REMAIN_INT}% ctx${RESET}   ${GREY}${COST_FMT} · ${MINS}m${SECS}s${RESET}"

# ============================================================================
# LINE 2 — directories + git
# ============================================================================
CWD=$(jqr '.workspace.current_dir // .cwd')
PROJ=$(jqr '.workspace.project_dir // empty')
[[ -z "$PROJ" ]] && PROJ="$CWD"

# Display paths with $HOME collapsed to ~.
tilde() { print -r -- "${1/#$HOME/~}" }

CWD_DISP=$(tilde "$CWD")
LINE2="${BLUE}📁 ${CWD_DISP}${RESET}"
if [[ "$PROJ" != "$CWD" ]]; then
  LINE2+="   ${DIM}proj: $(tilde "$PROJ")${RESET}"
fi

# Git: branch + dirty/clean + ahead/behind, computed from the cwd.
if git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$CWD" branch --show-current 2>/dev/null)
  [[ -z "$branch" ]] && branch="@$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)"
  changed=$(git -C "$CWD" status --porcelain 2>/dev/null | grep -c .)
  if (( changed > 0 )); then
    state="${RED}●${changed}${RESET}"
  else
    state="${GREEN}✓${RESET}"
  fi
  ab=$(git -C "$CWD" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  track=""
  if [[ -n "$ab" ]]; then
    ahead=${ab%%	*}; behind=${ab##*	}
    (( ahead  > 0 )) && track+=" ${YELLOW}↑${ahead}${RESET}"
    (( behind > 0 )) && track+=" ${YELLOW}↓${behind}${RESET}"
  fi
  LINE2+="   ${GREEN}🌿 ${branch}${RESET} ${state}${track}"
fi

# ============================================================================
# LINE 3 — plugins / skills / agents / hooks / MCP servers
# ============================================================================
# These counts are derived from config files, not the session JSON:
#   - enabled/total plugins:  $CLAUDE_DIR/settings.json .enabledPlugins
#   - marketplaces:           $CLAUDE_DIR/plugins/known_marketplaces.json
#   - plugin install paths:   $CLAUDE_DIR/plugins/installed_plugins.json
#   - user/project scopes:    ~/.claude and <project>/.claude directories
# Breakdowns are shown as (user/project/plugin); agents add a 4th = built-ins.

settings="$CLAUDE_DIR/settings.json"
installed="$CLAUDE_DIR/plugins/installed_plugins.json"
proj_settings="$PROJ/.claude/settings.json"

# Count skill directories (each holds a SKILL.md) under $1.
count_skills_dir() {
  local d="$1" n=0 s
  [[ -d "$d" ]] || { print 0; return }
  for s in "$d"/*(N/); do [[ -f "$s/SKILL.md" ]] && (( n++ )); done
  print $n
}
# Count *.md files directly under $1.
count_md() {
  local d="$1" f n=0
  [[ -d "$d" ]] || { print 0; return }
  for f in "$d"/*.md(N.); do (( n++ )); done
  print $n
}
# Count individual hook commands in a settings-style JSON file's .hooks block.
count_hooks_file() {
  local f="$1"
  [[ -f "$f" ]] || { print 0; return }
  jq -r '[.hooks // {} | to_entries[] | .value[] | (.hooks // [])[]] | length' "$f" 2>/dev/null || print 0
}
# Count entries in a .mcpServers object across the given JSON files.
count_mcp_files() {
  local f total=0 n
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    n=$(jq -r '.mcpServers // {} | length' "$f" 2>/dev/null || print 0)
    (( total += n ))
  done
  print $total
}

# --- plugins + marketplaces ---
PLUG_TOTAL=0; PLUG_ON=0
if [[ -f "$settings" ]]; then
  PLUG_TOTAL=$(jq -r '.enabledPlugins // {} | length' "$settings" 2>/dev/null || print 0)
  PLUG_ON=$(jq -r '[.enabledPlugins // {} | to_entries[] | select(.value == true)] | length' "$settings" 2>/dev/null || print 0)
fi
MKT=$(jq -r 'keys | length' "$CLAUDE_DIR/plugins/known_marketplaces.json" 2>/dev/null || print 0)

# --- user + project scoped counts ---
SKILLS_U=$(count_skills_dir "$CLAUDE_DIR/skills")
SKILLS_P=$(count_skills_dir "$PROJ/.claude/skills")
AGENTS_U=$(count_md "$CLAUDE_DIR/agents")
AGENTS_P=$(count_md "$PROJ/.claude/agents")
AGENTS_BUILTIN=6   # claude, claude-code-guide, Explore, general-purpose, Plan, statusline-setup
HOOKS_U=$(count_hooks_file "$settings")
HOOKS_P=$(count_hooks_file "$proj_settings")
MCP_U=$(count_mcp_files "$HOME/.claude.json" "$settings")
MCP_P=$(count_mcp_files "$PROJ/.mcp.json" "$proj_settings")

# --- enabled-plugin scoped counts ---
SKILLS_PL=0; AGENTS_PL=0; HOOKS_PL=0; MCP_PL=0
if [[ -f "$settings" && -f "$installed" ]]; then
  for key in ${(f)"$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$settings" 2>/dev/null)"}; do
    [[ -z "$key" ]] && continue
    ipath=$(jq -r --arg k "$key" '.plugins[$k][0].installPath // empty' "$installed" 2>/dev/null)
    [[ -z "$ipath" || ! -d "$ipath" ]] && continue
    (( SKILLS_PL += $(count_skills_dir "$ipath/skills") ))
    (( AGENTS_PL += $(count_md "$ipath/agents") ))
    (( HOOKS_PL  += $(count_hooks_file "$ipath/hooks/hooks.json") ))
    (( MCP_PL    += $(count_mcp_files "$ipath/.mcp.json") ))
  done
fi

SKILLS_TOTAL=$(( SKILLS_U + SKILLS_P + SKILLS_PL ))
AGENTS_TOTAL=$(( AGENTS_U + AGENTS_P + AGENTS_PL + AGENTS_BUILTIN ))
HOOKS_TOTAL=$(( HOOKS_U + HOOKS_P + HOOKS_PL ))
MCP_TOTAL=$(( MCP_U + MCP_P + MCP_PL ))

# MCP auth state is tracked inside Claude Code, not in any file a shell script
# can read reliably, so unauthenticated servers cannot be detected here. The
# orange-warning wiring is left in place: set MCP_WARN=1 if you find a usable
# signal. For now it stays 0 and the MCP segment uses its normal color.
MCP_WARN=0
if (( MCP_WARN )); then MCP_COLOR=$ORANGE; else MCP_COLOR=$GREY; fi

SEP="${DIM}  ·  ${RESET}"
LINE3="${GREY}🧩 ${PLUG_ON}/${PLUG_TOTAL} plugins · ${MKT} mkt${RESET}${SEP}"
LINE3+="${GREY}${SKILLS_TOTAL} skills (${SKILLS_U}/${SKILLS_P}/${SKILLS_PL})${RESET}${SEP}"
LINE3+="${GREY}${AGENTS_TOTAL} agents (${AGENTS_U}/${AGENTS_P}/${AGENTS_PL}/${AGENTS_BUILTIN})${RESET}${SEP}"
LINE3+="${GREY}${HOOKS_TOTAL} hooks (${HOOKS_U}/${HOOKS_P}/${HOOKS_PL})${RESET}${SEP}"
LINE3+="${MCP_COLOR}${MCP_TOTAL} MCPs (${MCP_U}/${MCP_P}/${MCP_PL})${RESET}"

# ============================================================================
print -r -- "$LINE1"
print -r -- "$LINE2"
print -r -- "$LINE3"
