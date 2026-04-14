#!/bin/sh
# ─────────────────────────────────────────────────────────
# continue_review.sh — Sends the last commit diff to
# Continue for automated code review.
#
# Priority:
#   A) cn -p  (Continue CLI, headless, reuses config/metrics)
#   B) OS automation: clipboard + keystrokes into Continue
#   C) Clipboard + notification with instructions
#
# Pure shell. No Python, no extra packages.
# Works on macOS, Linux, Windows (Git Bash / WSL).
# Supports: VS Code, IntelliJ IDEA, Rider, PyCharm.
# ─────────────────────────────────────────────────────────

GIT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
CR_DIR="$GIT_ROOT/.continue-review"
MAX_PATCH_CHARS=3500
REVIEW_FILE="$CR_DIR/state/last_review.md"

# ── helpers ──────────────────────────────────────────────

die_silent() { exit 0; }

msg() { printf '%s\n' "$1"; }

get_os() {
  case "$(uname -s)" in
    Darwin*)        echo "mac" ;;
    Linux*)         echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "win" ;;
    *)              echo "unknown" ;;
  esac
}

get_commit_info() {
  git -C "$GIT_ROOT" log -1 --pretty=format:"%h %s (%an)" 2>/dev/null || echo "unknown"
}

get_commit_short() {
  git -C "$GIT_ROOT" log -1 --pretty=format:"%h" 2>/dev/null || echo "?"
}

get_diff_stat() {
  git -C "$GIT_ROOT" diff HEAD~1 HEAD --no-color --stat=120 \
      -- . ":(exclude)*.lock" ":(exclude)package-lock.json" ":(exclude)*.min.*" \
      2>/dev/null || true
}

get_diff_patch() {
  _patch=$(git -C "$GIT_ROOT" diff HEAD~1 HEAD --no-color \
      -- . ":(exclude)*.lock" ":(exclude)package-lock.json" ":(exclude)*.min.*" \
      2>/dev/null || true)
  _len=${#_patch}
  if [ "$_len" -gt "$MAX_PATCH_CHARS" ] 2>/dev/null; then
    _patch="$(printf '%s' "$_patch" | head -c "$MAX_PATCH_CHARS")

[... diff truncated at ${MAX_PATCH_CHARS} chars. Run: git diff HEAD~1 HEAD]"
  fi
  printf '%s' "$_patch"
}

# ── build prompt ─────────────────────────────────────────

build_prompt() {
  _commit="$1"; _stat="$2"; _patch="$3"
  _prompt_tmp=$(mktemp)
  _tpl_file="$CR_DIR/config/review_prompt.txt"

  if [ -f "$_tpl_file" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
      case "$_line" in
        *'{commit}'*) printf '%s\n' "$_line" | sed "s|{commit}|$_commit|g" ;;
        *'{diff}'*)   printf '%s\n' "$_stat" ;;
        *'{patch}'*)  printf '%s\n' "$_patch" ;;
        *)            printf '%s\n' "$_line" ;;
      esac
    done < "$_tpl_file" > "$_prompt_tmp"
  else
    printf 'Review this commit: %s\n\nFiles changed:\n%s\n\n```diff\n%s\n```\n\nAnalyze: bugs, security, readability. Score 1-10. Be brief.\n' \
      "$_commit" "$_stat" "$_patch" > "$_prompt_tmp"
  fi
  cat "$_prompt_tmp"
  rm -f "$_prompt_tmp" 2>/dev/null
}

# ── notifications (native per OS) ────────────────────────

notify() {
  _title="$1"; _body="$2"
  case "$(get_os)" in
    mac)
      osascript -e "display notification \"$_body\" with title \"$_title\"" 2>/dev/null || true
      ;;
    linux)
      if command -v notify-send >/dev/null 2>&1; then
        notify-send "$_title" "$_body" 2>/dev/null || true
      fi
      ;;
    win)
      if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -Command "
          [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
          \$n = New-Object System.Windows.Forms.NotifyIcon
          \$n.Icon = [System.Drawing.SystemIcons]::Information
          \$n.BalloonTipTitle = '$_title'
          \$n.BalloonTipText = '$_body'
          \$n.Visible = \$true
          \$n.ShowBalloonTip(5000)
          Start-Sleep 5
          \$n.Dispose()
        " >/dev/null 2>&1 &
      fi
      ;;
  esac
}

# ── open file in IDE ─────────────────────────────────────

open_in_ide() {
  _file="$1"
  _ide=$(detect_running_ide)

  case "$_ide" in
    vscode)
      _code=$(command -v code 2>/dev/null || command -v code-insiders 2>/dev/null || true)
      [ -n "$_code" ] && "$_code" "$_file" >/dev/null 2>&1
      ;;
    intellij|rider|pycharm)
      _jb_cmd=""
      case "$_ide" in
        intellij) _jb_cmd=$(command -v idea 2>/dev/null || true) ;;
        rider)    _jb_cmd=$(command -v rider 2>/dev/null || true) ;;
        pycharm)  _jb_cmd=$(command -v pycharm 2>/dev/null || command -v charm 2>/dev/null || true) ;;
      esac
      [ -n "$_jb_cmd" ] && "$_jb_cmd" "$_file" >/dev/null 2>&1
      ;;
    *)
      # Best effort: try code, then open/xdg-open
      if command -v code >/dev/null 2>&1; then
        code "$_file" >/dev/null 2>&1
      elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$_file" >/dev/null 2>&1
      elif command -v open >/dev/null 2>&1; then
        open "$_file" >/dev/null 2>&1
      fi
      ;;
  esac
}

# ── detect running IDE ───────────────────────────────────

detect_running_ide() {
  # 1) Env vars set by IDE terminals
  if [ "${TERM_PROGRAM:-}" = "vscode" ] || [ -n "${VSCODE_GIT_IPC_HANDLE:-}" ]; then
    echo "vscode"; return
  fi
  if [ -n "${PYCHARM_HOSTED:-}" ]; then echo "pycharm"; return; fi
  if [ -n "${RIDER_INITIAL_DIRECTORY:-}" ]; then echo "rider"; return; fi
  for _k in INTELLIJ_ENVIRONMENT_READER IDEA_INITIAL_DIRECTORY JETBRAINS_IDE; do
    eval "_v=\${$_k:-}"
    [ -n "$_v" ] && { echo "intellij"; return; }
  done

  # 2) Check running processes
  case "$(get_os)" in
    mac)
      if pgrep -qf "Visual Studio Code" 2>/dev/null; then echo "vscode"; return; fi
      if pgrep -qf "IntelliJ IDEA" 2>/dev/null; then echo "intellij"; return; fi
      if pgrep -qf "Rider" 2>/dev/null; then echo "rider"; return; fi
      if pgrep -qf "PyCharm" 2>/dev/null; then echo "pycharm"; return; fi
      ;;
    linux)
      if pgrep -f "code" >/dev/null 2>&1; then echo "vscode"; return; fi
      if pgrep -f "idea" >/dev/null 2>&1; then echo "intellij"; return; fi
      if pgrep -f "rider" >/dev/null 2>&1; then echo "rider"; return; fi
      if pgrep -f "pycharm" >/dev/null 2>&1; then echo "pycharm"; return; fi
      ;;
    win)
      if command -v powershell.exe >/dev/null 2>&1; then
        _procs=$(powershell.exe -NoProfile -Command "Get-Process code,idea*,rider,pycharm* -EA 0 | Select -Exp Name" 2>/dev/null || true)
        case "$_procs" in
          *code*)    echo "vscode"; return ;;
          *idea*)    echo "intellij"; return ;;
          *rider*)   echo "rider"; return ;;
          *pycharm*) echo "pycharm"; return ;;
        esac
      fi
      ;;
  esac

  # 3) Fallback: check if CLI tools exist
  if command -v code >/dev/null 2>&1 || command -v code-insiders >/dev/null 2>&1; then
    echo "vscode"; return
  fi
  for _jb in idea rider pycharm charm; do
    if command -v "$_jb" >/dev/null 2>&1; then
      case "$_jb" in
        idea)            echo "intellij" ;;
        rider)           echo "rider" ;;
        pycharm|charm)   echo "pycharm" ;;
      esac
      return
    fi
  done
  echo "none"
}

# ── clipboard (all OS) ───────────────────────────────────

copy_to_clipboard() {
  _text="$1"
  case "$(get_os)" in
    mac)  printf '%s' "$_text" | pbcopy 2>/dev/null && return 0 ;;
    linux)
      if command -v xclip >/dev/null 2>&1; then
        printf '%s' "$_text" | xclip -selection clipboard 2>/dev/null && return 0
      elif command -v xsel >/dev/null 2>&1; then
        printf '%s' "$_text" | xsel --clipboard --input 2>/dev/null && return 0
      elif command -v wl-copy >/dev/null 2>&1; then
        printf '%s' "$_text" | wl-copy 2>/dev/null && return 0
      fi
      ;;
    win)  printf '%s' "$_text" | clip 2>/dev/null && return 0 ;;
  esac
  return 1
}

# ═══════════════════════════════════════════════════════
#  PLAN A: Continue CLI (cn -p)
# ═══════════════════════════════════════════════════════

find_cn() {
  command -v cn >/dev/null 2>&1 && { command -v cn; return 0; }
  for _p in \
    "$HOME/.local/bin/cn" \
    "$HOME/.npm-global/bin/cn" \
    "/usr/local/bin/cn" \
    "$HOME/.yarn/bin/cn" \
    "$HOME/.nvm/versions/node/*/bin/cn"; do
    for _expanded in $_p; do
      [ -x "$_expanded" ] 2>/dev/null && { echo "$_expanded"; return 0; }
    done
  done
  return 1
}

run_cn() {
  _cn="$1"; _prompt="$2"
  _cn_ver=$("$_cn" --version 2>/dev/null || echo "?")
  msg "  [i] Using Continue CLI (cn $_cn_ver)"

  _response=$(printf '%s' "$_prompt" | "$_cn" -p 2>/dev/null)
  _exit=$?

  if [ $_exit -ne 0 ] || [ -z "$_response" ]; then
    msg "  [!] cn -p failed (exit $_exit). Falling back to Plan B..."
    return 1
  fi

  # Save review as markdown
  _hash=$(get_commit_short)
  _date=$(date "+%Y-%m-%d %H:%M" 2>/dev/null || date)
  {
    printf '# Code Review — %s\n\n' "$_hash"
    printf '> Generated by Continue CLI on %s\n\n' "$_date"
    printf '%s\n' "$_response"
  } > "$REVIEW_FILE"

  msg "  [ok] Review complete."
  msg ""

  # Show the review in the terminal log
  msg "  ┌─────────────────────────────────────────────"
  printf '%s\n' "$_response" | while IFS= read -r _rline; do
    msg "  │ $_rline"
  done
  msg "  └─────────────────────────────────────────────"
  msg ""

  # Open review in the user's IDE
  open_in_ide "$REVIEW_FILE"

  # Notify
  notify "Continue Review" "Code review for $_hash is ready"

  return 0
}

try_plan_a() {
  _prompt="$1"

  # 1) cn already installed
  _cn=$(find_cn) && { run_cn "$_cn" "$_prompt" && return 0; }

  # 2) Try installing cn
  if command -v npm >/dev/null 2>&1; then
    msg "  [i] cn not found. Installing @continuedev/cli..."
    if npm install -g @continuedev/cli >/dev/null 2>&1; then
      msg "  [ok] cn installed."
      _cn=$(find_cn) && { run_cn "$_cn" "$_prompt" && return 0; }
    else
      msg "  [!] npm install failed (permissions?). Trying npx..."
    fi
  fi

  # 3) npx (no persistent install)
  if command -v npx >/dev/null 2>&1; then
    msg "  [i] Trying cn via npx (one-time)..."
    _response=$(printf '%s' "$_prompt" | npx -y @continuedev/cli -p 2>/dev/null) || return 1
    if [ -n "$_response" ]; then
      _hash=$(get_commit_short)
      _date=$(date "+%Y-%m-%d %H:%M" 2>/dev/null || date)
      { printf '# Code Review — %s\n\n> Generated via npx on %s\n\n%s\n' "$_hash" "$_date" "$_response"; } > "$REVIEW_FILE"
      msg "  [ok] Review complete (via npx)."
      msg ""
      msg "  ┌─────────────────────────────────────────────"
      printf '%s\n' "$_response" | while IFS= read -r _rline; do msg "  │ $_rline"; done
      msg "  └─────────────────────────────────────────────"
      msg ""
      open_in_ide "$REVIEW_FILE"
      notify "Continue Review" "Code review for $_hash is ready"
      return 0
    fi
  fi

  return 1
}

# ═══════════════════════════════════════════════════════
#  PLAN B: OS automation (clipboard → IDE → paste → send)
# ═══════════════════════════════════════════════════════

# -- VS Code automation --------------------------------

auto_vscode_mac() {
  osascript -e '
    tell application "Visual Studio Code" to activate
    delay 0.8
    tell application "System Events"
      keystroke "l" using command down
      delay 0.6
      keystroke "v" using command down
      delay 0.3
      key code 36
    end tell
  ' >/dev/null 2>&1
}

auto_vscode_linux() {
  command -v xdotool >/dev/null 2>&1 || return 1
  _wid=$(xdotool search --name "Visual Studio Code" 2>/dev/null | head -1)
  [ -z "$_wid" ] && return 1
  xdotool windowactivate "$_wid" 2>/dev/null
  sleep 0.8
  xdotool key ctrl+l
  sleep 0.6
  xdotool key ctrl+v
  sleep 0.3
  xdotool key Return
}

auto_vscode_win() {
  command -v powershell.exe >/dev/null 2>&1 || return 1
  powershell.exe -NoProfile -Command '
    Add-Type -AssemblyName Microsoft.VisualBasic
    Add-Type -AssemblyName System.Windows.Forms
    $p = Get-Process code -EA 0 | Select -First 1
    if ($p) {
      [Microsoft.VisualBasic.Interaction]::AppActivate($p.Id)
      Start-Sleep -Milliseconds 800
      [System.Windows.Forms.SendKeys]::SendWait("^l")
      Start-Sleep -Milliseconds 600
      [System.Windows.Forms.SendKeys]::SendWait("^v")
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    } else { exit 1 }
  ' >/dev/null 2>&1
}

# -- JetBrains automation (same shortcut: Ctrl+L) ------

auto_jetbrains_mac() {
  _app_name="$1"  # "IntelliJ IDEA", "Rider", "PyCharm"
  osascript -e "
    tell application \"$_app_name\" to activate
    delay 0.8
    tell application \"System Events\"
      keystroke \"l\" using command down
      delay 0.6
      keystroke \"v\" using command down
      delay 0.3
      key code 36
    end tell
  " >/dev/null 2>&1
}

auto_jetbrains_linux() {
  _proc_name="$1"  # "idea", "rider", "pycharm"
  command -v xdotool >/dev/null 2>&1 || return 1
  _wid=$(xdotool search --name "$_proc_name" 2>/dev/null | head -1)
  # Also try capitalized
  [ -z "$_wid" ] && _wid=$(xdotool search --class "$_proc_name" 2>/dev/null | head -1)
  [ -z "$_wid" ] && return 1
  xdotool windowactivate "$_wid" 2>/dev/null
  sleep 0.8
  xdotool key ctrl+l
  sleep 0.6
  xdotool key ctrl+v
  sleep 0.3
  xdotool key Return
}

auto_jetbrains_win() {
  _proc_name="$1"  # "idea64", "rider64", "pycharm64"
  command -v powershell.exe >/dev/null 2>&1 || return 1
  powershell.exe -NoProfile -Command "
    Add-Type -AssemblyName Microsoft.VisualBasic
    Add-Type -AssemblyName System.Windows.Forms
    \$p = Get-Process ${_proc_name}* -EA 0 | Select -First 1
    if (\$p) {
      [Microsoft.VisualBasic.Interaction]::AppActivate(\$p.Id)
      Start-Sleep -Milliseconds 800
      [System.Windows.Forms.SendKeys]::SendWait('^l')
      Start-Sleep -Milliseconds 600
      [System.Windows.Forms.SendKeys]::SendWait('^v')
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    } else { exit 1 }
  " >/dev/null 2>&1
}

# -- dispatch automation per IDE + OS ------------------

try_plan_b() {
  _prompt="$1"
  _ide=$(detect_running_ide)
  _os=$(get_os)

  [ "$_ide" = "none" ] && return 1
  copy_to_clipboard "$_prompt" || return 1

  _ok=false
  case "$_ide" in
    vscode)
      case "$_os" in
        mac)   auto_vscode_mac   && _ok=true ;;
        linux) auto_vscode_linux && _ok=true ;;
        win)   auto_vscode_win   && _ok=true ;;
      esac
      ;;
    intellij)
      case "$_os" in
        mac)   auto_jetbrains_mac "IntelliJ IDEA"  && _ok=true ;;
        linux) auto_jetbrains_linux "idea"          && _ok=true ;;
        win)   auto_jetbrains_win "idea"            && _ok=true ;;
      esac
      ;;
    rider)
      case "$_os" in
        mac)   auto_jetbrains_mac "Rider"    && _ok=true ;;
        linux) auto_jetbrains_linux "rider"  && _ok=true ;;
        win)   auto_jetbrains_win "rider"    && _ok=true ;;
      esac
      ;;
    pycharm)
      case "$_os" in
        mac)   auto_jetbrains_mac "PyCharm"   && _ok=true ;;
        linux) auto_jetbrains_linux "pycharm" && _ok=true ;;
        win)   auto_jetbrains_win "pycharm"   && _ok=true ;;
      esac
      ;;
  esac

  if [ "$_ok" = true ]; then
    msg "  [ok] Prompt sent to Continue in $_ide automatically."
    notify "Continue Review" "Review prompt sent to $_ide"
    return 0
  fi

  return 1
}

# ═══════════════════════════════════════════════════════
#  PLAN C: Clipboard + notification
# ═══════════════════════════════════════════════════════

try_plan_c() {
  _prompt="$1"

  # Save to file regardless
  _tmp=""
  case "$(get_os)" in
    win) _tmp="${TEMP:-/tmp}/continue_review_prompt.md" ;;
    *)   _tmp="/tmp/continue_review_prompt.md" ;;
  esac
  printf '%s' "$_prompt" > "$_tmp"

  if copy_to_clipboard "$_prompt"; then
    msg "  [ok] Prompt copied to clipboard."
    msg "       Open Continue (Cmd+L / Ctrl+L) -> Paste (Cmd+V / Ctrl+V) -> Enter"
    notify "Continue Review" "Review prompt copied to clipboard. Paste in Continue."
  else
    msg "  [i] Prompt saved to: $_tmp"
    msg "      Open it and paste contents into Continue."
    notify "Continue Review" "Review prompt saved to $_tmp"
  fi
}

# ── logging ──────────────────────────────────────────────

log_entry() {
  _method="$1"; _commit="$2"; _ide="$3"
  _logfile="$CR_DIR/state/log.txt"
  _date=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date)
  _user="${USER:-${USERNAME:-unknown}}"
  printf '%s | %s | %s | %s | %s\n' "$_date" "$_user" "$_method" "$_ide" "$_commit" >> "$_logfile"
}

# ── main ─────────────────────────────────────────────────

main() {
  mkdir -p "$CR_DIR/state"

  _patch=$(get_diff_patch)
  [ -z "$_patch" ] && die_silent

  _commit=$(get_commit_info)
  _stat=$(get_diff_stat)
  _prompt=$(build_prompt "$_commit" "$_stat" "$_patch")
  _ide=$(detect_running_ide)

  msg ""
  msg "  Continue Code Review — $_commit"
  msg "  IDE: $_ide | OS: $(get_os)"
  msg ""

  _method="none"

  # Plan A: cn CLI (best — headless, reuses config, metrics work)
  if try_plan_a "$_prompt"; then
    _method="cn-cli"
  # Plan B: OS automation (clipboard + keystrokes into Continue extension)
  elif try_plan_b "$_prompt"; then
    _method="os-auto"
  # Plan C: clipboard + notification
  else
    try_plan_c "$_prompt"
    _method="clipboard"
  fi

  log_entry "$_method" "$_commit" "$_ide"
  msg ""
}

main "$@"
