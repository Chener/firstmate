#!/usr/bin/env bash
# Live Kimi startup-signal guard (live-harness-optin family).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate opt-in FM_KIMI_SIGNALS_LIVE kimi tmux git

TMP_ROOT=$(fm_test_tmproot fm-kimi-signals-live)
LAB="$TMP_ROOT/lab"
KIMI_HOME="$TMP_ROOT/home"
SOCKET="fm-kimi-signals-$$"
SESSION=kimi-signals
TARGET="$SESSION:probe"
VERSION=$(kimi --version 2>&1 | head -1)

fail_live() {
  fail "real Kimi $VERSION: $1"
}

cleanup_kimi_signals_live() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
  rm -rf "$TMP_ROOT"
}
trap cleanup_kimi_signals_live EXIT

mkdir -p "$LAB/.kimi" "$KIMI_HOME/.kimi-code"
git -C "$LAB" init -q
[ -f "${HOME}/.kimi-code/config.toml" ] \
  || fail_live "authenticated user config is unavailable"
[ -d "${HOME}/.kimi-code/credentials" ] \
  || fail_live "authenticated user credentials are unavailable"
ln -s "${HOME}/.kimi-code/config.toml" "$KIMI_HOME/.kimi-code/config.toml" \
  || fail_live "could not bind the authenticated user config into the isolated home"
ln -s "${HOME}/.kimi-code/credentials" "$KIMI_HOME/.kimi-code/credentials" \
  || fail_live "could not bind the authenticated user credentials into the isolated home"
printf '%s\n' \
  '{' \
  '  "mcpServers": {' \
  '    "fm-trust-probe": {' \
  '      "command": "/usr/bin/true",' \
  '      "args": []' \
  '    }' \
  '  }' \
  '}' > "$LAB/.kimi/mcp.json"
printf '%s\n' '# Live Kimi probe' '' \
  'Reply with exactly `KIMI_PROBE_OK` and do not use tools.' > "$LAB/brief.md"

tmux -L "$SOCKET" new-session -d -s "$SESSION" -n probe -c "$LAB" \
  "env HOME='$KIMI_HOME' '$(command -v kimi)' --auto"

capture=
for _ in $(seq 1 40); do
  capture=$(tmux -L "$SOCKET" capture-pane -p -t "$TARGET" -S -80 2>/dev/null || true)
  printf '%s\n' "$capture" | grep -Fq 'Trust this folder?' && break
  sleep 0.25
done
printf '%s\n' "$capture" | grep -Fq 'Trust this folder?' \
  || fail_live "project-level MCP trust dialog did not appear"
printf '%s\n' "$capture" | grep -Fq '❯ Trust this folder' \
  || fail_live "project-level MCP trust choice was not selected"
tmux -L "$SOCKET" send-keys -t "$TARGET" Enter

for _ in $(seq 1 40); do
  capture=$(tmux -L "$SOCKET" capture-pane -p -t "$TARGET" -S -80 2>/dev/null || true)
  printf '%s\n' "$capture" | grep -Fq 'context: 0% (0/256k)' && break
  sleep 0.25
done
printf '%s\n' "$capture" | grep -Fq 'context: 0% (0/256k)' \
  || fail_live "trust acceptance did not reach Kimi's ready composer"

pointer="Read the brief at $LAB/brief.md and follow it exactly."
tmux -L "$SOCKET" send-keys -t "$TARGET" -l "$pointer"
tmux -L "$SOCKET" send-keys -t "$TARGET" Enter

pending=0
for _ in $(seq 1 20); do
  capture=$(tmux -L "$SOCKET" capture-pane -p -t "$TARGET" -S -80 2>/dev/null || true)
  if printf '%s\n' "$capture" | grep -Fq 'Read the brief at' \
     && printf '%s\n' "$capture" | grep -Fq 'context: 0% (0/256k)'; then
    pending=1
    break
  fi
  sleep 0.1
done
[ "$pending" -eq 1 ] || fail_live "immediate Enter did not reproduce a pending pointer"

for attempt in $(seq 1 3); do
  tmux -L "$SOCKET" send-keys -t "$TARGET" Enter
  for _ in $(seq 1 20); do
    capture=$(tmux -L "$SOCKET" capture-pane -p -t "$TARGET" -S -100 2>/dev/null || true)
    printf '%s\n' "$capture" | grep -qE 'Session:[[:space:]]+session_[[:alnum:]_-]+' && break 2
    sleep 0.25
  done
done
for _ in $(seq 1 60); do
  capture=$(tmux -L "$SOCKET" capture-pane -p -t "$TARGET" -S -100 2>/dev/null || true)
  if printf '%s\n' "$capture" | grep -qE 'Session:[[:space:]]+session_[[:alnum:]_-]+' \
     && printf '%s\n' "$capture" | grep -Fq '✨ Read the brief at'; then
    break
  fi
  sleep 0.25
done
printf '%s\n' "$capture" | grep -qE 'Session:[[:space:]]+session_[[:alnum:]_-]+' \
  || fail_live "retry Enter did not allocate a session"
printf '%s\n' "$capture" | grep -Fq '✨ Read the brief at' \
  || fail_live "retry Enter did not echo the submitted pointer"

pass "real Kimi $VERSION answers project MCP trust, retries pending input without retyping, and exposes an allocated session before context growth"
