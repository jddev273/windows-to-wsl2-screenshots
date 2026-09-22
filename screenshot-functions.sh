#!/bin/bash

# Windows-to-WSL2 Screenshot Automation Functions
# Auto-saves screenshots from Windows clipboard to WSL2 and manages clipboard sync

_screenshot_monitor_dir() {
    printf '%s\n' "$HOME/.screenshots"
}

_screenshot_monitor_pid_file() {
    printf '%s/monitor.pid\n' "$(_screenshot_monitor_dir)"
}

_screenshot_monitor_ready_file() {
    printf '%s/monitor.ready\n' "$(_screenshot_monitor_dir)"
}

_screenshot_monitor_stop_file() {
    printf '%s/monitor.stop\n' "$(_screenshot_monitor_dir)"
}

_screenshot_monitor_start_time() {
    local pid="$1"
    if [ -r "/proc/$pid/stat" ]; then
        awk '{print $22}' "/proc/$pid/stat" 2>/dev/null
    fi
}

_screenshot_monitor_state() {
    local pid_file pid start_time
    pid_file="$(_screenshot_monitor_pid_file)"
    [ -r "$pid_file" ] || return 1

    read -r pid start_time < "$pid_file" || return 1
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac

    printf '%s %s\n' "$pid" "${start_time:-0}"
}

_screenshot_monitor_running() {
    local state pid recorded_start current_start
    state="$(_screenshot_monitor_state)" || return 1
    read -r pid recorded_start <<< "$state"

    kill -0 "$pid" 2>/dev/null || return 1

    # Refuse a stale PID file if the Linux/WSL PID has been reused.
    if [ "$recorded_start" != "0" ] && [ -r "/proc/$pid/stat" ]; then
        current_start="$(_screenshot_monitor_start_time "$pid")"
        [ -n "$current_start" ] && [ "$current_start" = "$recorded_start" ] || return 1
    fi

    return 0
}

_screenshot_monitor_remove_stale_state() {
    if ! _screenshot_monitor_running; then
        rm -f "$(_screenshot_monitor_pid_file)"
    fi
}

# Start the auto-screenshot monitor.
start-screenshot-monitor() {
    echo "🚀 Starting Windows-to-WSL2 screenshot automation..."

    local screenshots_dir script_dir ps_script log_file pid_file ready_file stop_file windows_save_dir windows_ps_script
    screenshots_dir="$(_screenshot_monitor_dir)"
    pid_file="$(_screenshot_monitor_pid_file)"
    ready_file="$(_screenshot_monitor_ready_file)"
    stop_file="$(_screenshot_monitor_stop_file)"
    log_file="$screenshots_dir/monitor.log"

    mkdir -p "$screenshots_dir" || {
        echo "❌ Could not create screenshots directory: $screenshots_dir"
        return 1
    }

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    ps_script="$script_dir/auto-clipboard-monitor.ps1"

    if [ ! -f "$ps_script" ]; then
        echo "❌ PowerShell script not found at: $ps_script"
        return 1
    fi
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "❌ powershell.exe was not found from WSL"
        echo "💡 Windows interop must be enabled and Windows executables must be on PATH"
        return 1
    fi
    if ! command -v wslpath >/dev/null 2>&1; then
        echo "❌ wslpath was not found"
        return 1
    fi

    if _screenshot_monitor_running || [ -f "$ready_file" ]; then
        echo "ℹ️ Replacing the existing screenshot monitor..."
        stop-screenshot-monitor >/dev/null || {
            echo "❌ Existing monitor did not stop cleanly; refusing to start a duplicate"
            return 1
        }
    else
        _screenshot_monitor_remove_stale_state
        rm -f "$ready_file" "$stop_file"
    fi

    windows_save_dir="$(wslpath -w "$screenshots_dir")" || {
        echo "❌ Could not convert the WSL screenshot directory to a Windows path"
        return 1
    }
    windows_ps_script="$(wslpath -w "$ps_script")" || {
        echo "❌ Could not convert the PowerShell script path to a Windows path"
        return 1
    }

    nohup powershell.exe \
        -NoProfile \
        -Sta \
        -WindowStyle Hidden \
        -ExecutionPolicy Bypass \
        -File "$windows_ps_script" \
        -SaveDirectory "$windows_save_dir" \
        -WslSaveDirectory "$screenshots_dir" \
        > "$log_file" 2>&1 &

    local pid start_time i started=0
    pid=$!
    start_time="$(_screenshot_monitor_start_time "$pid")"
    printf '%s %s\n' "$pid" "${start_time:-0}" > "$pid_file"

    # PowerShell creates monitor.ready only after its Windows-side prerequisites
    # and save directory have initialized. This avoids treating the WSL interop
    # relay alone as proof that the monitor is usable.
    for i in {1..50}; do
        if [ -f "$ready_file" ] && _screenshot_monitor_running; then
            started=1
            break
        fi
        _screenshot_monitor_running || break
        sleep 0.1
    done

    if [ "$started" -ne 1 ]; then
        # Leave a graceful stop request for any Windows process that outlived
        # its WSL relay. Do not claim success merely because a relay PID existed.
        printf '%s\n' stop > "$stop_file" 2>/dev/null || true
        if ! _screenshot_monitor_running; then
            rm -f "$pid_file" "$ready_file"
        fi
        echo "❌ Screenshot monitor failed to become ready"
        echo "📄 Last monitor log lines:"
        tail -n 20 "$log_file" 2>/dev/null || true
        return 1
    fi

    sleep 0.2
    if ! _screenshot_monitor_running || [ ! -f "$ready_file" ]; then
        printf '%s\n' stop > "$stop_file" 2>/dev/null || true
        _screenshot_monitor_running || rm -f "$pid_file" "$ready_file"
        echo "❌ Screenshot monitor exited during startup"
        echo "📄 Last monitor log lines:"
        tail -n 20 "$log_file" 2>/dev/null || true
        return 1
    fi

    echo "✅ SCREENSHOT AUTOMATION IS NOW RUNNING!"
    echo ""
    echo "🔥 MAGIC WORKFLOW:"
    echo "   1. Take screenshot (Win+Shift+S, Win+PrintScreen, etc.)"
    echo "   2. Image automatically saved to $screenshots_dir/"
    echo "   3. WSL path automatically copied to the Windows/WSL clipboard"
    echo "   4. Just Ctrl+V in Claude Code or any application!"
    echo ""
    echo "📁 Images save to: $screenshots_dir/"
    echo "🔗 Latest always at: $screenshots_dir/latest.png"
    echo "📋 Drag & drop images to $screenshots_dir/ also works!"
}

# Stop the monitor by asking the Windows PowerShell loop to exit itself.
# This avoids depending on WSL signal propagation to terminate a Windows process.
stop-screenshot-monitor() {
    echo "🛑 Stopping screenshot automation..."

    local state pid="" i ready_file stop_file
    ready_file="$(_screenshot_monitor_ready_file)"
    stop_file="$(_screenshot_monitor_stop_file)"

    if state="$(_screenshot_monitor_state)" && _screenshot_monitor_running; then
        read -r pid _ <<< "$state"
    elif [ ! -f "$ready_file" ]; then
        rm -f "$(_screenshot_monitor_pid_file)" "$stop_file"
        echo "ℹ️ Screenshot automation is not running"
        return 0
    fi

    if ! printf '%s\n' stop > "$stop_file"; then
        echo "❌ Could not write monitor stop request: $stop_file"
        return 1
    fi

    for i in {1..50}; do
        if ! _screenshot_monitor_running && [ ! -f "$ready_file" ]; then
            break
        fi
        sleep 0.1
    done

    if _screenshot_monitor_running || [ -f "$ready_file" ]; then
        echo "❌ Screenshot monitor did not stop cleanly"
        echo "💡 A stop request was left at: $stop_file"
        echo "💡 Run troubleshoot-screenshots and inspect the monitor log"
        return 1
    fi

    if [ -n "$pid" ]; then
        wait "$pid" 2>/dev/null || true
    fi
    rm -f "$(_screenshot_monitor_pid_file)" "$ready_file" "$stop_file"

    echo "✅ Screenshot automation stopped"
}

# Check both the tracked WSL interop relay and the Windows-authored ready marker.
check-screenshot-monitor() {
    local ready_file
    ready_file="$(_screenshot_monitor_ready_file)"

    if _screenshot_monitor_running && [ -f "$ready_file" ]; then
        local state pid
        state="$(_screenshot_monitor_state)"
        read -r pid _ <<< "$state"
        echo "✅ Screenshot automation is running (PID $pid)"
        echo "🔥 Just take screenshots - everything is automatic!"
        echo "📁 Saves to: $HOME/.screenshots/"
        echo "📋 Paths automatically copied to clipboard for easy pasting!"
        return 0
    fi

    if [ -f "$ready_file" ]; then
        echo "⚠️ Windows monitor reports ready but its tracked WSL relay is missing or stale"
        echo "💡 Run: stop-screenshot-monitor"
        return 1
    fi

    if _screenshot_monitor_running; then
        echo "⚠️ Screenshot monitor process exists but Windows has not reported ready"
        echo "💡 Run: troubleshoot-screenshots"
        return 1
    fi

    _screenshot_monitor_remove_stale_state
    echo "❌ Screenshot automation not running"
    echo "💡 Start with: start-screenshot-monitor"
    return 1
}

# Compatibility name documented by older README versions and PR #2.
check-screenshot-status() {
    check-screenshot-monitor
}

# Run bounded diagnostics without changing WSL distro configuration.
troubleshoot-screenshots() {
    local failures=0 screenshots_dir script_dir ps_script windows_path
    screenshots_dir="$(_screenshot_monitor_dir)"
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    ps_script="$script_dir/auto-clipboard-monitor.ps1"

    echo "🔍 Screenshot automation diagnostics"

    if command -v powershell.exe >/dev/null 2>&1; then
        echo "✅ powershell.exe is available"
    else
        echo "❌ powershell.exe is not available from WSL"
        failures=$((failures + 1))
    fi

    if command -v wslpath >/dev/null 2>&1; then
        if windows_path="$(wslpath -w "$screenshots_dir" 2>/dev/null)"; then
            echo "✅ WSL path converts to: $windows_path"
        else
            echo "❌ wslpath could not convert: $screenshots_dir"
            failures=$((failures + 1))
        fi
    else
        echo "❌ wslpath is not available"
        failures=$((failures + 1))
    fi

    if [ -f "$ps_script" ]; then
        echo "✅ PowerShell monitor script found: $ps_script"
    else
        echo "❌ PowerShell monitor script missing: $ps_script"
        failures=$((failures + 1))
    fi

    if _screenshot_monitor_running && [ -f "$(_screenshot_monitor_ready_file)" ]; then
        echo "✅ Tracked screenshot monitor is running and Windows reports ready"
    elif [ -f "$(_screenshot_monitor_ready_file)" ]; then
        echo "⚠️ Windows monitor reports ready but the tracked WSL relay is missing or stale"
        failures=$((failures + 1))
    elif _screenshot_monitor_running; then
        echo "⚠️ Tracked WSL relay exists but Windows has not reported ready"
        failures=$((failures + 1))
    else
        echo "ℹ️ Tracked screenshot monitor is not running"
    fi

    if [ -f "$screenshots_dir/monitor.log" ]; then
        echo ""
        echo "📄 Last monitor log lines:"
        tail -n 10 "$screenshots_dir/monitor.log"
    fi

    if [ "$failures" -eq 0 ]; then
        echo "✅ Core prerequisites look good"
        return 0
    fi

    echo "❌ Found $failures core prerequisite problem(s)"
    return 1
}

# Quick access to latest image path
latest-screenshot() {
    echo "$HOME/.screenshots/latest.png"
}

# Copy latest image path to clipboard
copy-latest-screenshot() {
    if [ -f "$HOME/.screenshots/latest.png" ]; then
        echo "$HOME/.screenshots/latest.png" | clip.exe
        echo "✅ Copied to clipboard: $HOME/.screenshots/latest.png"
    else
        echo "❌ No latest screenshot found"
        echo "💡 Take a screenshot first (Win+Shift+S)"
    fi
}

# Copy specific image path to clipboard
copy-screenshot() {
    if [ -n "$1" ]; then
        local path="$HOME/.screenshots/$1"
        if [ -f "$HOME/.screenshots/$1" ]; then
            echo "$path" | clip.exe
            echo "✅ Copied to clipboard: $path"
        else
            echo "❌ File not found: $path"
            list-screenshots
        fi
    else
        echo "Usage: copy-screenshot <filename>"
        echo ""
        list-screenshots
    fi
}

# List available screenshots
list-screenshots() {
    echo "📸 Available screenshots:"
    if ls "$HOME/.screenshots/"*.png 2>/dev/null | grep -v latest; then
        echo ""
        echo "💡 Use 'copy-screenshot <filename>' to copy path to clipboard"
    else
        echo "   No screenshots found"
        echo "💡 Take a screenshot (Win+Shift+S) to get started!"
    fi
}

# Open screenshots directory
open-screenshots() {
    if command -v explorer.exe > /dev/null; then
        explorer.exe "$(wslpath -w "$HOME/.screenshots")"
    elif command -v nautilus > /dev/null; then
        nautilus "$HOME/.screenshots"
    else
        echo "📁 Screenshots directory: $HOME/.screenshots/"
        ls -la "$HOME/.screenshots/"
    fi
}

# Clean old screenshots (keep last N files)
clean-screenshots() {
    local keep=${1:-10}
    echo "🧹 Cleaning old screenshots, keeping latest $keep files..."
    
    cd "$HOME/.screenshots" || return 1
    
    # Count files (excluding latest.png)
    local count=$(ls -1 screenshot_*.png 2>/dev/null | wc -l)
    
    if [ "$count" -gt "$keep" ]; then
        ls -1t screenshot_*.png | tail -n +$((keep + 1)) | xargs rm -f
        echo "✅ Cleaned $((count - keep)) old screenshots"
    else
        echo "✅ No cleaning needed (only $count screenshots found)"
    fi
}

# Show help
screenshot-help() {
    echo "🚀 Windows-to-WSL2 Screenshot Automation"
    echo ""
    echo "📋 Available commands:"
    echo "  start-screenshot-monitor    - Start the automation"
    echo "  stop-screenshot-monitor     - Stop the automation"
    echo "  check-screenshot-monitor    - Check if running"
    echo "  check-screenshot-status     - Compatibility status command"
    echo "  troubleshoot-screenshots    - Run monitor diagnostics"
    echo "  latest-screenshot           - Get path to latest screenshot"
    echo "  copy-latest-screenshot      - Copy latest screenshot path to clipboard"
    echo "  copy-screenshot <file>      - Copy specific screenshot path to clipboard"
    echo "  list-screenshots            - List all available screenshots"
    echo "  open-screenshots            - Open screenshots directory"
    echo "  clean-screenshots [count]   - Clean old screenshots (default: keep 10)"
    echo "  screenshot-help             - Show this help"
    echo ""
    echo "🔥 Quick start:"
    echo "  1. Run: start-screenshot-monitor"
    echo "  2. Take screenshots with Win+Shift+S"
    echo "  3. Paths are automatically copied to clipboard!"
    echo "  4. Just Ctrl+V in Claude Code!"
}

# Aliases for convenience
alias screenshots='list-screenshots'
alias latest='latest-screenshot'
alias copy-latest='copy-latest-screenshot'
alias start-screenshots='start-screenshot-monitor'
alias stop-screenshots='stop-screenshot-monitor'
alias check-screenshots='check-screenshot-monitor'