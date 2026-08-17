#!/usr/bin/env bash
# Bounce Ghostty's Dock icon repeatedly until the terminal regains focus.
#
# Ghostty's `attention` bell feature maps to macOS requestUserAttention with an
# *informational* request, which bounces the icon exactly once. The repeating
# variant (NSCriticalRequest) is not exposed by any Ghostty config option, and
# an outside process cannot request attention on another app's behalf. So the
# only way to keep Ghostty bouncing is to re-send BEL on an interval.
#
# Exits immediately when Ghostty is already frontmost, so it never nags while
# you are actively watching the session.

set -u

script_name="$(basename "${BASH_SOURCE[0]}")"

# Plugin userConfig values arrive as CLAUDE_PLUGIN_OPTION_<KEY>. Fall back to
# the bare env vars so the script still works when run standalone.
GHOSTTY_BUNDLE_ID="${CLAUDE_PLUGIN_OPTION_BUNDLE_ID:-${GHOSTTY_BUNDLE_ID:-com.mitchellh.ghostty}}"
INTERVAL_SECONDS="${CLAUDE_PLUGIN_OPTION_INTERVAL_SECONDS:-${CLAUDE_NAG_INTERVAL_SECONDS:-10}}"
MAX_SECONDS="${CLAUDE_PLUGIN_OPTION_MAX_SECONDS:-${CLAUDE_NAG_MAX_SECONDS:-300}}"

# Focus detection is macOS-only and depends on lsappinfo. Anywhere else, do
# nothing rather than spin a loop that can never see the terminal come back.
[[ "$(uname -s)" == "Darwin" ]] || exit 0
command -v lsappinfo >/dev/null 2>&1 || exit 0

# A hook process has no controlling terminal of its own: `ps -o tty=` reports
# "??" and /dev/tty fails with "Device not configured". So walk up the process
# chain to find the pty owned by the claude process and write to that device
# directly. Never use /dev/tty here, it will always fail.
resolve_tty_device() {
  local pid="$$" name ppid level=0
  while ((level < 6)); do
    name="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' \n')"
    if [[ -n "$name" && "$name" != "??" && -w "/dev/$name" ]]; then
      printf '%s' "/dev/$name"
      return 0
    fi
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' \n')"
    [[ -n "$ppid" && "$ppid" != "0" && "$ppid" != "1" && "$ppid" != "$pid" ]] || return 1
    pid="$ppid"
    level=$((level + 1))
  done
  return 1
}

tty_device="$(resolve_tty_device)" || exit 0

# One nag loop per terminal: supersede any loop left over from a prior turn.
# Confirm the recorded pid is still one of ours before signalling it, otherwise
# a recycled pid means we kill an unrelated process.
#
# SIGKILL, not SIGTERM, for two reasons. Bash defers a caught signal until the
# foreground command finishes, so a TERM'd predecessor keeps belling until its
# `sleep` elapses and two loops overlap for up to one interval. And its EXIT
# trap would then delete the pid file we are about to claim. There is nothing
# to clean up in a bell loop, so killing it outright is both correct and quiet.
pid_file="${TMPDIR:-/tmp}/claude-ghostty-nag-$(basename "$tty_device").pid"
if [[ -r "$pid_file" ]]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && ((old_pid != $$)) &&
    ps -o command= -p "$old_pid" 2>/dev/null | grep -q "$script_name"; then
    kill -9 "$old_pid" 2>/dev/null || true
  fi
fi
echo $$ >"$pid_file"

# Only clear the file if it is still ours. A successor may have claimed it
# while we were winding down, and deleting its claim would let a third run
# start a duplicate loop.
cleanup() {
  [[ "$(cat "$pid_file" 2>/dev/null)" == "$$" ]] && rm -f "$pid_file"
  return 0
}
trap cleanup EXIT

# lsappinfo needs no Accessibility permission, unlike osascript/System Events.
ghostty_is_focused() {
  local front
  front="$(lsappinfo front 2>/dev/null)" || return 1
  [[ -n "$front" ]] || return 1
  lsappinfo info -only bundleid "$front" 2>/dev/null | grep -q "$GHOSTTY_BUNDLE_ID"
}

ghostty_is_focused && exit 0

elapsed=0
while ((elapsed < MAX_SECONDS)); do
  ghostty_is_focused && break
  printf '\a' >"$tty_device" 2>/dev/null || break
  sleep "$INTERVAL_SECONDS"
  elapsed=$((elapsed + INTERVAL_SECONDS))
done
