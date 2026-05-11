#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# skills install — install skills to your agent of choice
# ============================================================
# Usage:
#   ./install.sh                      # interactive picker
#   ./install.sh --target claude      # install all skills to Claude Code
#   ./install.sh --target claude --skill review-fix-loop
#   ./install.sh --target generic --dir /path/to/project
#   ./install.sh --target cursor --level user
#   ./install.sh --list               # list available skills
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR"
TARGET=""
SKILL=""
LEVEL="project"   # project | user
DRY_RUN=false
LIST_ONLY=false
PROJECT_DIR=""    # project root (set by --dir)
TARGET_DIR=""     # final install dir (set by resolver)

# ---- helpers ----

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

say()   { printf '%b\n' "$*"; }
info()  { printf '%b\n' "${CYAN}[info]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[ ok ]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[warn]${NC} $*"; }
err()   { printf '%b\n' "${RED}[err ]${NC} $*" >&2; }
die()   { err "$@"; exit 1; }

available_skills() {
  for d in "$SKILLS_SRC"/*/; do
    [ ! -d "$d" ] && continue
    local name
    name="$(basename "$d")"
    [ "$name" = "lib" ] && continue
    [ -f "$d/SKILL.md" ] && echo "$name"
  done
}

# ---- target registry ----
# Two parallel arrays: TARGET_KEYS and TARGET_LABELS
TARGET_KEYS=(
  generic
  claude
  opencode
  codex
  cursor
  traycer
  aider
  windsurf
  continue
  amp
)

TARGET_LABELS=(
  "Generic — .agents/skills/ (works with Claude Code, OpenCode, etc.)"
  "Claude Code — .claude/skills/"
  "OpenCode — .opencode/skills/"
  "Codex (OpenAI) — .codex/skills/"
  "Cursor — .cursor/skills/"
  "Traycer — .traycer/skills/"
  "Aider — .aider/skills/"
  "Windsurf — .windsurf/skills/"
  "Continue — .continue/skills/"
  "Amp — .amp/skills/"
)

target_label() {
  local key="$1"
  local i
  for i in "${!TARGET_KEYS[@]}"; do
    if [ "${TARGET_KEYS[$i]}" = "$key" ]; then
      echo "${TARGET_LABELS[$i]}"
      return 0
    fi
  done
  return 1
}

target_index() {
  local key="$1"
  local i
  for i in "${!TARGET_KEYS[@]}"; do
    if [ "${TARGET_KEYS[$i]}" = "$key" ]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

# ---- target resolvers ----
# Each resolve_<target> sets:
#   TARGET_DIR         - where to install
#   INSTALL_STRATEGY   - copy | symlink | symlink-project

_project_root() {
  if [ -n "$PROJECT_DIR" ]; then
    echo "$PROJECT_DIR"
  else
    pwd
  fi
}

resolve_generic() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agents/skills"
  else
    TARGET_DIR="$(_project_root)/.agents/skills"
  fi
}

resolve_claude() {
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.claude/skills"
    INSTALL_STRATEGY="symlink"
  else
    TARGET_DIR="$(_project_root)/.claude/skills"
    INSTALL_STRATEGY="symlink-project"
  fi
}

resolve_opencode() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
  else
    TARGET_DIR="$(_project_root)/.opencode/skills"
  fi
}

resolve_codex() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.codex/skills"
  else
    TARGET_DIR="$(_project_root)/.codex/skills"
  fi
}

resolve_cursor() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.cursor/skills"
  else
    TARGET_DIR="$(_project_root)/.cursor/skills"
  fi
}

resolve_traycer() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.traycer/skills"
  else
    TARGET_DIR="$(_project_root)/.traycer/skills"
  fi
}

resolve_aider() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.aider/skills"
  else
    TARGET_DIR="$(_project_root)/.aider/skills"
  fi
}

resolve_windsurf() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.windsurf/skills"
  else
    TARGET_DIR="$(_project_root)/.windsurf/skills"
  fi
}

resolve_continue() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.continue/skills"
  else
    TARGET_DIR="$(_project_root)/.continue/skills"
  fi
}

resolve_amp() {
  INSTALL_STRATEGY="copy"
  if [ "$LEVEL" = "user" ]; then
    TARGET_DIR="$HOME/.amp/skills"
  else
    TARGET_DIR="$(_project_root)/.amp/skills"
  fi
}

# ---- install strategies ----

do_install() {
  local skill_name="$1"
  local src="$SKILLS_SRC/$skill_name"
  local dst="$TARGET_DIR/$skill_name"

  [ -d "$src" ] || die "Skill '$skill_name' not found at $src"

  info "Installing ${YELLOW}$skill_name${NC} → ${CYAN}$dst${NC}"

  case "$INSTALL_STRATEGY" in
    copy)
      if $DRY_RUN; then
        say "  [dry-run] cp -r $src $dst"
      else
        mkdir -p "$(dirname "$dst")"
        rm -rf "$dst"
        cp -r "$src" "$dst"
      fi
      ;;
    symlink)
      if $DRY_RUN; then
        say "  [dry-run] ln -sf $src $dst"
      else
        mkdir -p "$(dirname "$dst")"
        rm -f "$dst"
        ln -sf "$src" "$dst"
      fi
      ;;
    symlink-project)
      local proj_root agents_dir
      proj_root="$(_project_root)"
      agents_dir="$proj_root/.agents/skills"

      if ! $DRY_RUN; then
        mkdir -p "$agents_dir"
        rm -rf "$agents_dir/$skill_name"
        cp -r "$src" "$agents_dir/$skill_name"

        mkdir -p "$TARGET_DIR"
        rm -f "$dst"
        ln -sf "../../.agents/skills/$skill_name" "$dst"
      else
        say "  [dry-run] cp -r $src → $agents_dir/$skill_name"
        say "  [dry-run] ln -sf ../../.agents/skills/$skill_name → $dst"
      fi
      ;;
  esac

  ok "Installed $skill_name"
}

# ---- UI ----

interactive_pick() {
  echo ""
  say "${CYAN}╔══════════════════════════════════════╗${NC}"
  say "${CYAN}║        skills installer              ║${NC}"
  say "${CYAN}╚══════════════════════════════════════╝${NC}"
  echo ""

  # --- pick target ---
  say "Available targets:"
  echo ""
  local targets=()
  local idx=1
  local t
  for t in "${TARGET_KEYS[@]}"; do
    printf "  ${GREEN}%2d${NC}) %s\n" "$idx" "$(target_label "$t")"
    targets+=("$t")
    idx=$((idx + 1))
  done
  echo ""
  read -rp "  Pick target [1-${#targets[@]}]: " pick
  if [ "$pick" -ge 1 ] 2>/dev/null && [ "$pick" -le "${#targets[@]}" ] 2>/dev/null; then
    TARGET="${targets[$((pick - 1))]}"
  else
    die "Invalid selection"
  fi

  # --- pick level ---
  echo ""
  say "Install level:"
  echo "  ${GREEN}1${NC}) project (current directory)"
  echo "  ${GREEN}2${NC}) user   (home directory, available globally)"
  echo ""
  read -rp "  Pick level [1-2] (default: 1): " lpick
  case "${lpick:-1}" in
    1) LEVEL="project" ;;
    2) LEVEL="user" ;;
    *) die "Invalid selection" ;;
  esac

  # --- pick skills ---
  echo ""
  local skills=()
  local s
  while IFS= read -r s; do
    [ -n "$s" ] && skills+=("$s")
  done < <(available_skills)

  say "Available skills:"
  echo "  ${GREEN}0${NC}) ALL skills"
  local sidx=1
  for s in "${skills[@]}"; do
    printf "  ${GREEN}%2d${NC}) %s\n" "$sidx" "$s"
    sidx=$((sidx + 1))
  done
  echo ""
  read -rp "  Pick skill [0-${#skills[@]}] (default: 0): " spick
  case "${spick:-0}" in
    0) SKILL="" ;;
    *)
      if [ "$spick" -ge 1 ] 2>/dev/null && [ "$spick" -le "${#skills[@]}" ] 2>/dev/null; then
        SKILL="${skills[$((spick - 1))]}"
      else
        die "Invalid selection"
      fi
      ;;
  esac

  # resolve target dir for project-level
  if [ "$LEVEL" = "project" ]; then
    echo ""
    read -rp "  Project directory [$(pwd)]: " pdir
    PROJECT_DIR="${pdir:-$(pwd)}"
  fi
}

# ---- argument parsing ----

show_help() {
  cat <<'EOF'
skills install — install skills to your agent of choice

Usage:
  ./install.sh                              interactive
  ./install.sh --target <agent> [options]   non-interactive

Options:
  --target <agent>    Agent to install to. One of:
                      generic, claude, opencode, codex, cursor,
                      traycer, aider, windsurf, continue, amp
  --skill <name>      Install a specific skill (default: all)
  --level <lvl>       project (default) | user
  --dir <path>        Project directory (default: pwd)
  --dry-run           Show what would be done without doing it
  --list              List available skills and targets
  --help              Show this message
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        TARGET="$2"; shift 2 ;;
      --skill)
        SKILL="$2"; shift 2 ;;
      --level)
        LEVEL="$2"; shift 2 ;;
      --dir)
        PROJECT_DIR="$2"; shift 2 ;;
      --dry-run)
        DRY_RUN=true; shift ;;
      --list)
        LIST_ONLY=true; shift ;;
      --help)
        show_help; exit 0 ;;
      *)
        die "Unknown option: $1. Use --help." ;;
    esac
  done
}

# ---- list ----

do_list() {
  echo ""
  say "${CYAN}Targets:${NC}"
  local i
  for i in "${!TARGET_KEYS[@]}"; do
    printf "  ${GREEN}%-14s${NC} %s\n" "${TARGET_KEYS[$i]}" "${TARGET_LABELS[$i]}"
  done
  echo ""
  say "${CYAN}Skills:${NC}"
  local s
  while IFS= read -r s; do
    [ -n "$s" ] && printf "  ${GREEN}%s${NC}\n" "$s"
  done < <(available_skills)
  echo ""
}

# ---- main ----

main() {
  parse_args "$@"

  if $LIST_ONLY; then
    do_list
    exit 0
  fi

  # interactive mode if no target specified
  if [ -z "$TARGET" ]; then
    interactive_pick
  fi

  # validate target
  if ! target_label "$TARGET" > /dev/null 2>&1; then
    die "Unknown target: '$TARGET'. Use --list to see available targets."
  fi

  # validate level
  if [ "$LEVEL" != "project" ] && [ "$LEVEL" != "user" ]; then
    die "Level must be 'project' or 'user'."
  fi

  # resolve target paths (calls resolve_<target>)
  "resolve_$TARGET"

  # install skills
  echo ""
  say "${CYAN}╔══════════════════════════════════════╗${NC}"
  say "${CYAN}║  Target:${NC} ${GREEN}$TARGET${NC} ($LEVEL-level)"
  say "${CYAN}║  Dir:   ${NC} ${TARGET_DIR}"
  say "${CYAN}╚══════════════════════════════════════╝${NC}"
  echo ""

  if [ -n "$SKILL" ]; then
    do_install "$SKILL"
  else
    local skills=()
    local s
    while IFS= read -r s; do
      [ -n "$s" ] && skills+=("$s")
    done < <(available_skills)

    if [ ${#skills[@]} -eq 0 ]; then
      warn "No skills found in $SKILLS_SRC"
      exit 0
    fi

    for s in "${skills[@]}"; do
      do_install "$s"
    done
  fi

  echo ""
  ok "Done."
}

main "$@"
