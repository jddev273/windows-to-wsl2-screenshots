#!/bin/bash

# Windows-to-WSL2 Screenshot Automation Functions
# Auto-saves screenshots from Windows clipboard to WSL2 and manages clipboard sync

# Start the auto-screenshot monitor
start-screenshot-monitor() {
    echo "🚀 Starting Windows-to-WSL2 screenshot automation..."
    
    # Kill any existing monitors
    pkill -f "auto-clipboard-monitor.ps1" 2>/dev/null || true
    
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
    
    # Start the monitor in background
    nohup powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "$ps_script" > "$HOME/.screenshots/monitor.log" 2>&1 &
    
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
    pkill -f "auto-clipboard-monitor.ps1" 2>/dev/null || true
    echo "✅ Screenshot automation stopped"
}

# Check if running
check-screenshot-monitor() {
    # Check for the PowerShell process running our script
    if pgrep -f "auto-clipboard-monitor.ps1" > /dev/null 2>&1; then
        echo "✅ Screenshot automation is running"
        echo "🔥 Just take screenshots - everything is automatic!"
        echo "📁 Saves to: $HOME/.screenshots/"
        echo "📋 Paths automatically copied to clipboard for easy pasting!"
        
        # Show recent log entries if available
        if [ -f "$HOME/.screenshots/monitor.log" ]; then
            echo ""
            echo "📝 Recent activity (last 5 lines from log):"
            tail -n 5 "$HOME/.screenshots/monitor.log" 2>/dev/null || echo "   (log file empty or unreadable)"
        fi
    else
        echo "❌ Screenshot automation not running"
        echo "💡 Start with: start-screenshot-monitor"
        
        # Check if log file exists and show last few lines for troubleshooting
        if [ -f "$HOME/.screenshots/monitor.log" ]; then
            echo ""
            echo "📝 Last log entries (for troubleshooting):"
            tail -n 10 "$HOME/.screenshots/monitor.log" 2>/dev/null || echo "   (log file empty or unreadable)"
        fi
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

# Troubleshooting function to help diagnose issues
troubleshoot-screenshots() {
    echo "🔧 Screenshot Automation Troubleshooting"
    echo ""
    
    # Check if PowerShell is available
    if command -v powershell.exe > /dev/null; then
        echo "✅ PowerShell is available"
    else
        echo "❌ PowerShell not found - this tool requires Windows with WSL2"
        return 1
    fi
    
    # Check if clip.exe is available
    if command -v clip.exe > /dev/null; then
        echo "✅ clip.exe is available for clipboard operations"
    else
        echo "⚠️  clip.exe not found - clipboard sync may not work"
    fi
    
    # Check if screenshots directory exists
    if [ -d "$HOME/.screenshots" ]; then
        echo "✅ Screenshots directory exists: $HOME/.screenshots"
        local count=$(ls -1 "$HOME/.screenshots"/*.png 2>/dev/null | wc -l)
        echo "   📁 Contains $count PNG files"
    else
        echo "⚠️  Screenshots directory doesn't exist yet: $HOME/.screenshots"
    fi
    
    # Check if PowerShell script exists
    local script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    local ps_script="$script_dir/auto-clipboard-monitor.ps1"
    if [ -f "$ps_script" ]; then
        echo "✅ PowerShell script found: $ps_script"
    else
        echo "❌ PowerShell script not found: $ps_script"
    fi
    
    # Check if monitor is running
    if pgrep -f "auto-clipboard-monitor.ps1" > /dev/null 2>&1; then
        echo "✅ Screenshot monitor is currently running"
    else
        echo "⚠️  Screenshot monitor is not running"
    fi
    
    # Check log file
    if [ -f "$HOME/.screenshots/monitor.log" ]; then
        echo "✅ Log file exists: $HOME/.screenshots/monitor.log"
        local log_size=$(stat -c%s "$HOME/.screenshots/monitor.log" 2>/dev/null || echo "0")
        echo "   📝 Log file size: $log_size bytes"
        if [ "$log_size" -gt 0 ]; then
            echo ""
            echo "📝 Last 10 lines from log:"
            tail -n 10 "$HOME/.screenshots/monitor.log"
        else
            echo "   (log file is empty)"
        fi
    else
        echo "⚠️  No log file found - monitor may not have been started yet"
    fi
    
    echo ""
    echo "💡 Common issues and solutions:"
    echo "   • If monitor won't start: Check that you're running from the correct directory"
    echo "   • If screenshots aren't detected: Try using Windows Terminal instead of basic WSL terminal"
    echo "   • If clipboard doesn't work: Make sure clip.exe is available in your WSL environment"
    echo "   • Check the log file for detailed error messages"
}

# Alias for backward compatibility
check-screenshot-status() {
    check-screenshot-monitor
}

# Show help
screenshot-help() {
    echo "🚀 Windows-to-WSL2 Screenshot Automation"
    echo ""
    echo "📋 Available commands:"
    echo "  start-screenshot-monitor    - Start the automation"
    echo "  stop-screenshot-monitor     - Stop the automation"
    echo "  check-screenshot-monitor    - Check if running"
    echo "  check-screenshot-status     - Check if running (alias)"
    echo "  latest-screenshot           - Get path to latest screenshot"
    echo "  copy-latest-screenshot      - Copy latest screenshot path to clipboard"
    echo "  copy-screenshot <file>      - Copy specific screenshot path to clipboard"
    echo "  list-screenshots            - List all available screenshots"
    echo "  open-screenshots            - Open screenshots directory"
    echo "  clean-screenshots [count]   - Clean old screenshots (default: keep 10)"
    echo "  troubleshoot-screenshots    - Run troubleshooting diagnostics"
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
alias check-screenshot-status='check-screenshot-monitor'
alias troubleshoot='troubleshoot-screenshots'