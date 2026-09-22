#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
original_home="$HOME"
fake_bin="$tmp_dir/bin"
export HOME="$tmp_dir/home with spaces"
export SCREENSHOT_TEST_ARGS_FILE="$tmp_dir/powershell-args.txt"
mkdir -p "$fake_bin" "$HOME"

cleanup() {
    if [ -f "$HOME/.screenshots/monitor.pid" ]; then
        stop-screenshot-monitor >/dev/null 2>&1 || true
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

cat > "$fake_bin/wslpath" <<'EOF'
#!/usr/bin/env bash
if [ "${SCREENSHOT_TEST_WSLPATH_FAIL:-0}" = "1" ]; then
    exit 7
fi
[ "${1:-}" = "-w" ] || exit 2
case "${2:-}" in
    */auto-clipboard-monitor.ps1)
        printf '%s\n' 'C:\WSL Bridge\auto-clipboard-monitor.ps1'
        ;;
    *)
        printf '%s\n' 'C:\WSL Bridge\shots'
        ;;
esac
EOF

cat > "$fake_bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SCREENSHOT_TEST_ARGS_FILE"
if [ "${SCREENSHOT_TEST_FAIL:-0}" = "1" ]; then
    echo "MOCK_POWERSHELL_FAILURE" >&2
    exit 23
fi

ready_file="$HOME/.screenshots/monitor.ready"
stop_file="$HOME/.screenshots/monitor.stop"
printf '%s\n' "$$" > "$ready_file"

cleanup() {
    rm -f "$ready_file" "$stop_file"
}
trap cleanup EXIT

# Deliberately ignore TERM/INT so the test proves stop uses the control-file
# handshake rather than depending on Linux signal delivery.
trap ':' TERM INT

while :; do
    if [ -f "$stop_file" ]; then
        exit 0
    fi
    sleep 0.05
done
EOF

chmod +x "$fake_bin/wslpath" "$fake_bin/powershell.exe"
export PATH="$fake_bin:$PATH"

# shellcheck source=../screenshot-functions.sh
source "$repo_dir/screenshot-functions.sh"

if check-screenshot-monitor >/dev/null 2>&1; then
    fail "monitor reported running before start"
fi

start-screenshot-monitor >/dev/null
[ -f "$HOME/.screenshots/monitor.pid" ] || fail "PID state was not created"
[ -f "$HOME/.screenshots/monitor.ready" ] || fail "Windows-side readiness marker was not observed"
[ ! -e "$HOME/.screenshots/monitor.stop" ] || fail "stale stop request remained after start"
check-screenshot-monitor >/dev/null || fail "canonical status command did not see the monitor"
check-screenshot-status >/dev/null || fail "compatibility status command did not see the monitor"

grep -Fx -- "-File" "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null || fail "PowerShell File switch missing"
grep -Fx -- 'C:\WSL Bridge\auto-clipboard-monitor.ps1' "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null || fail "PowerShell script path was not converted to one Windows argv element"
if grep -Fx -- "$repo_dir/auto-clipboard-monitor.ps1" "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null; then
    fail "Linux PowerShell script path leaked across the Windows executable boundary"
fi
grep -Fx -- "-SaveDirectory" "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null || fail "SaveDirectory switch missing"
grep -Fx -- 'C:\WSL Bridge\shots' "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null || fail "Windows save path was not one argv element"
grep -Fx -- "-WslSaveDirectory" "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null || fail "WslSaveDirectory switch missing"
grep -Fx -- "$HOME/.screenshots" "$SCREENSHOT_TEST_ARGS_FILE" >/dev/null || fail "WSL path was not one argv element"

stop-screenshot-monitor >/dev/null
[ ! -e "$HOME/.screenshots/monitor.pid" ] || fail "PID state remained after stop"
[ ! -e "$HOME/.screenshots/monitor.ready" ] || fail "readiness marker remained after stop"
[ ! -e "$HOME/.screenshots/monitor.stop" ] || fail "stop request remained after graceful stop"
if check-screenshot-monitor >/dev/null 2>&1; then
    fail "monitor still reported running after stop"
fi

# A stale/reused PID record must never kill an unrelated live process.
sleep 20 &
unrelated_pid=$!
unrelated_start="$(awk '{print $22}' "/proc/$unrelated_pid/stat")"
printf '%s %s\n' "$unrelated_pid" "$((unrelated_start + 1))" > "$HOME/.screenshots/monitor.pid"
if _screenshot_monitor_running; then
    fail "stale start-time record was accepted"
fi
stop-screenshot-monitor >/dev/null
kill -0 "$unrelated_pid" 2>/dev/null || fail "stale PID handling killed an unrelated process"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true

# Immediate PowerShell failure must be surfaced instead of reporting success.
export SCREENSHOT_TEST_FAIL=1
if start-screenshot-monitor >"$tmp_dir/start-failure.out" 2>&1; then
    fail "immediate PowerShell failure was reported as success"
fi
unset SCREENSHOT_TEST_FAIL
[ ! -e "$HOME/.screenshots/monitor.pid" ] || fail "failed start left PID state behind"
grep -F "MOCK_POWERSHELL_FAILURE" "$HOME/.screenshots/monitor.log" >/dev/null || fail "startup failure log was not preserved"

# Path conversion failure must abort before monitor launch.
export SCREENSHOT_TEST_WSLPATH_FAIL=1
if start-screenshot-monitor >"$tmp_dir/wslpath-failure.out" 2>&1; then
    fail "wslpath failure was reported as success"
fi
unset SCREENSHOT_TEST_WSLPATH_FAIL
[ ! -e "$HOME/.screenshots/monitor.pid" ] || fail "wslpath failure left PID state behind"

# PowerShell must consume explicit paths rather than rediscover distro/user state.
ps_script="$repo_dir/auto-clipboard-monitor.ps1"
grep -F 'WslSaveDirectory' "$ps_script" >/dev/null || fail "PowerShell WSL path parameter missing"
grep -F 'Clipboard]::SetText' "$ps_script" >/dev/null || fail "PowerShell clipboard write missing"
if grep -Eq 'WslDistro|WslUsername|wsl\.exe|Ubuntu-22\.04' "$ps_script"; then
    fail "PowerShell still contains distro/user rediscovery"
fi

# Documentation and command surface must agree.
grep -F 'check-screenshot-monitor' "$repo_dir/README.md" >/dev/null || fail "README canonical status command missing"
grep -F 'check-screenshot-status' "$repo_dir/README.md" >/dev/null || fail "README compatibility status command missing"

echo "PASS: screenshot bridge lifecycle and path-contract tests"
