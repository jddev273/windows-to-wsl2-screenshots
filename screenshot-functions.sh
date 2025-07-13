#!/bin/bash

# Windows-to-WSL2 Screenshot Automation Functions
# Auto-saves screenshots from Windows clipboard to WSL2 and manages clipboard sync

# Start the auto-screenshot monitor with optional ShareX support
start-screenshot-monitor() {
    local sharex_path=""
    local watch_dirs=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sharex-path)
                sharex_path="$2"
                shift 2
                ;;
            --watch-dir)
                if [ -n "$watch_dirs" ]; then
                    watch_dirs="$watch_dirs,$2"
                else
                    watch_dirs="$2"
                fi
                shift 2
                ;;
            --no-sharex)
                sharex_path="none"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: start-screenshot-monitor [--sharex-path PATH] [--watch-dir PATH] [--no-sharex]"
                return 1
                ;;
        esac
    done
    
    echo "🚀 Starting enhanced Windows-to-WSL2 screenshot automation..."
    
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
    
    # Build PowerShell command with parameters
    local ps_cmd="powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File \"$ps_script\""
    
    if [ -n "$sharex_path" ]; then
        ps_cmd="$ps_cmd -ShareXPath \"$sharex_path\""
    fi
    
    if [ -n "$watch_dirs" ]; then
        ps_cmd="$ps_cmd -WatchDirectories @(\"${watch_dirs//,/\",\"}\")"
    fi
    
    # Start the monitor in background
    nohup bash -c "$ps_cmd" > "$HOME/.screenshots/monitor.log" 2>&1 &
    
    echo "✅ SCREENSHOT AUTOMATION IS NOW RUNNING!"
    echo ""
    echo "🔥 ENHANCED WORKFLOW:"
    echo "   1. Take screenshots with:"
    echo "      • Win+Shift+S (Windows Snipping Tool)"
    echo "      • ShareX (auto-detected)"
    echo "      • Any screenshot tool saving to monitored directories"
    echo "   2. Images automatically saved to $HOME/.screenshots/"
    echo "   3. Paths automatically copied to both Windows & WSL2 clipboards!"
    echo "   4. Just Ctrl+V in Claude Code or any application!"
    echo ""
    echo "📁 Images save to: $HOME/.screenshots/"
    echo "🔗 Latest always at: $HOME/.screenshots/latest.png"
    echo "📋 Drag & drop images to $HOME/.screenshots/ also works!"
    
    if [ -n "$sharex_path" ] && [ "$sharex_path" != "none" ]; then
        echo "📸 ShareX path: $sharex_path"
    fi
    
    if [ -n "$watch_dirs" ]; then
        echo "👀 Additional watch dirs: $watch_dirs"
    fi
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
    echo "🚀 Enhanced Windows-to-WSL2 Screenshot Automation"
    echo ""
    echo "📋 Available commands:"
    echo "  start-screenshot-monitor [options]  - Start the automation"
    echo "    Options:"
    echo "      --sharex-path PATH    - Specify custom ShareX directory"
    echo "      --watch-dir PATH      - Add additional directory to monitor"
    echo "      --no-sharex          - Disable ShareX auto-detection"
    echo "  stop-screenshot-monitor             - Stop the automation"
    echo "  check-screenshot-monitor            - Check if running"
    echo "  latest-screenshot                   - Get path to latest screenshot"
    echo "  copy-latest-screenshot              - Copy latest screenshot path to clipboard"
    echo "  copy-screenshot <file>              - Copy specific screenshot path to clipboard"
    echo "  list-screenshots                    - List all available screenshots"
    echo "  open-screenshots                    - Open screenshots directory"
    echo "  clean-screenshots [count]           - Clean old screenshots (default: keep 10)"
    echo "  screenshot-help                     - Show this help"
    echo ""
    echo "🔥 Quick start:"
    echo "  1. Run: start-screenshot-monitor"
    echo "  2. Take screenshots with:"
    echo "     • Win+Shift+S (Windows Snipping Tool)"
    echo "     • ShareX (auto-detected)"
    echo "     • Any screenshot tool"
    echo "  3. Paths are automatically copied to clipboard!"
    echo "  4. Just Ctrl+V in Claude Code!"
    echo ""
    echo "📸 ShareX Integration:"
    echo "  • Auto-detects common ShareX paths"
    echo "  • Monitors ShareX screenshot directories"
    echo "  • Works with your existing ShareX workflow"
}

# Aliases for convenience
alias screenshots='list-screenshots'
alias latest='latest-screenshot'
alias copy-latest='copy-latest-screenshot'
alias start-screenshots='start-screenshot-monitor'
alias stop-screenshots='stop-screenshot-monitor'
alias check-screenshots='check-screenshot-monitor'