#!/bin/bash

# Windows-to-WSL2 Screenshot Automation Functions
# Auto-saves screenshots from Windows clipboard to WSL2 and manages clipboard sync

# Start the auto-screenshot monitor
start-screenshot-monitor() {
    local wsl_distro="${1:-auto}"
    
    echo "🚀 Starting Windows-to-WSL2 screenshot automation..."
    
    # Kill any existing monitors
    pkill -f "auto-clipboard-monitor" 2>/dev/null || true
    
    # Create screenshots directory in home
    mkdir -p "$HOME/.screenshots"
    
    # Get current directory to find the PowerShell script
    local script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    local ps_script="$script_dir/auto-clipboard-monitor.ps1"
    
    if [ ! -f "$ps_script" ]; then
        echo "❌ PowerShell script not found at: $ps_script"
        echo "💡 Make sure auto-clipboard-monitor.ps1 is in the same directory as this script"
        return 1
    fi
    
    # If WSL distro is specified, pass it to PowerShell
    local ps_args=""
    if [ "$wsl_distro" != "auto" ]; then
        ps_args="-WslDistro \"$wsl_distro\""
        echo "📦 Using specified WSL distribution: $wsl_distro"
    fi
    
    # Start the monitor in background
    nohup powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "$ps_script" $ps_args > "$HOME/.screenshots/monitor.log" 2>&1 &
    
    echo "✅ SCREENSHOT AUTOMATION IS NOW RUNNING!"
    echo ""
    echo "🔥 MAGIC WORKFLOW:"
    echo "   1. Take screenshot (Win+Shift+S, Win+PrintScreen, etc.)"
    echo "   2. Image automatically saved to $HOME/.screenshots/"
    echo "   3. Path automatically copied to both Windows & WSL2 clipboards!"
    echo "   4. Just Ctrl+V in Claude Code or any application!"
    echo ""
    echo "📁 Images save to: $HOME/.screenshots/"
    echo "🔗 Latest always at: $HOME/.screenshots/latest.png"
    echo "📋 Drag & drop images to $HOME/.screenshots/ also works!"
}

# Stop the monitor
stop-screenshot-monitor() {
    echo "🛑 Stopping screenshot automation..."
    pkill -f "auto-clipboard-monitor" 2>/dev/null || true
    echo "✅ Screenshot automation stopped"
}

# Check if running
check-screenshot-monitor() {
    if pgrep -f "auto-clipboard-monitor" > /dev/null 2>&1; then
        echo "✅ Screenshot automation is running"
        echo "🔥 Just take screenshots - everything is automatic!"
        echo "📁 Saves to: $HOME/.screenshots/"
        echo "📋 Paths automatically copied to clipboard for easy pasting!"
    else
        echo "❌ Screenshot automation not running"
        echo "💡 Start with: start-screenshot-monitor"
    fi
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
    echo "  start-screenshot-monitor [distro] - Start the automation (optional: specify WSL distro)"
    echo "  stop-screenshot-monitor           - Stop the automation"
    echo "  check-screenshot-monitor          - Check if running"
    echo "  latest-screenshot                 - Get path to latest screenshot"
    echo "  copy-latest-screenshot            - Copy latest screenshot path to clipboard"
    echo "  copy-screenshot <file>            - Copy specific screenshot path to clipboard"
    echo "  list-screenshots                  - List all available screenshots"
    echo "  open-screenshots                  - Open screenshots directory"
    echo "  clean-screenshots [count]         - Clean old screenshots (default: keep 10)"
    echo "  screenshot-help                   - Show this help"
    echo ""
    echo "🔥 Quick start:"
    echo "  1. Run: start-screenshot-monitor"
    echo "     Or specify distro: start-screenshot-monitor Ubuntu-22.04"
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