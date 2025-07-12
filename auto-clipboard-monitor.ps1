# Enhanced screenshot monitor supporting both Windows clipboard and ShareX
param(
    [string]$SaveDirectory = "~/.screenshots",
    [string]$WslDistro = "auto",
    [string]$ShareXPath = "auto",
    [string[]]$WatchDirectories = @()
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Convert the tilde path to WSL format
if ($SaveDirectory -eq "~/.screenshots") {
    # Try to auto-detect WSL distribution if auto mode is used
    if ($WslDistro -eq "auto") {
        $WslDistros = @(wsl.exe -l -q | Where-Object { 
            $_ -and $_.Trim() -ne "" -and $_ -notlike "*docker*" 
        } | ForEach-Object { 
            $_.Trim() -replace '\s+', '' -replace '\x00', ''
        })
        if ($WslDistros.Count -gt 0) {
            $WslDistro = $WslDistros[0]
            Write-Host "Auto-detected WSL distribution: $WslDistro"
        }
    }
    
    # Get the actual WSL username instead of Windows username
    $WslUsername = wsl.exe -d $WslDistro -e whoami
    $WslUsername = $WslUsername.Trim()
    $SaveDirectory = "\\wsl.localhost\$WslDistro\home\$WslUsername\.screenshots"
}

if (!(Test-Path $SaveDirectory)) {
    New-Item -ItemType Directory -Path $SaveDirectory -Force | Out-Null
}

# Auto-detect ShareX installation and path
function Get-ShareXPath {
    $possiblePaths = @(
        "$env:USERPROFILE\Documents\ShareX\Screenshots",
        "$env:USERPROFILE\OneDrive\Documents\ShareX\Screenshots", 
        "$env:USERPROFILE\OneDrive\Documentos\ShareX\Screenshots",
        "$env:USERPROFILE\Pictures\ShareX\Screenshots",
        "$env:APPDATA\ShareX\Screenshots"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            # Find the most recent subdirectory (usually YYYY-MM format)
            $latestDir = Get-ChildItem $path -Directory | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -First 1
            if ($latestDir) {
                return $latestDir.FullName
            }
            return $path
        }
    }
    return $null
}

# Setup ShareX monitoring if enabled
$ShareXWatcher = $null
if ($ShareXPath -eq "auto") {
    $detectedPath = Get-ShareXPath
    if ($detectedPath) {
        $ShareXPath = $detectedPath
        Write-Host "Auto-detected ShareX path: $ShareXPath"
    }
} elseif ($ShareXPath -ne "none" -and $ShareXPath -ne "") {
    if (!(Test-Path $ShareXPath)) {
        Write-Warning "ShareX path not found: $ShareXPath"
        $ShareXPath = $null
    }
}

# Setup file system watchers for additional directories
$watchers = @()
$allWatchPaths = @()
if ($ShareXPath) { $allWatchPaths += $ShareXPath }
$allWatchPaths += $WatchDirectories

foreach ($watchPath in $allWatchPaths) {
    if (Test-Path $watchPath) {
        try {
            $watcher = New-Object System.IO.FileSystemWatcher
            $watcher.Path = $watchPath
            $watcher.Filter = "*.*"
            $watcher.NotifyFilter = [System.IO.NotifyFilters]::CreationTime
            $watcher.EnableRaisingEvents = $true
            $watchers += $watcher
            Write-Host "Monitoring directory: $watchPath"
        } catch {
            Write-Warning "Could not setup watcher for: $watchPath"
        }
    }
}

Write-Host "WINDOWS-TO-WSL2 SCREENSHOT AUTOMATION STARTED"
Write-Host "Auto-saving images to: $SaveDirectory"
if ($ShareXPath) { Write-Host "ShareX monitoring: $ShareXPath" }
if ($WatchDirectories.Count -gt 0) { Write-Host "Additional directories: $($WatchDirectories -join ', ')" }
Write-Host "Press Ctrl+C to stop"



Write-Host "Monitoring clipboard events and directory changes..."
$previousHash = $null
$lastFileTime = Get-Date

# Function to copy path to both clipboards
function Set-BothClipboards($path) {
    try {
        [System.Windows.Forms.Clipboard]::SetText($path)
        $wslCommand = "echo '$path' | clip.exe"
        wsl.exe -d $WslDistro -e bash -c $wslCommand
        return $true
    } catch {
        Start-Sleep -Milliseconds 200
        try {
            [System.Windows.Forms.Clipboard]::SetText($path)
            $wslCommand = "echo '$path' | clip.exe" 
            wsl.exe -d $WslDistro -e bash -c $wslCommand
            return $true
        } catch {
            Write-Warning "Could not set clipboard: $_"
            return $false
        }
    }
}

while ($true) {
    try {
        Start-Sleep -Milliseconds 500
        
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            $image = [System.Windows.Forms.Clipboard]::GetImage()
            if ($image) {
                $ms = New-Object System.IO.MemoryStream
                $image.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $imageBytes = $ms.ToArray()
                $ms.Dispose()
                $currentHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($imageBytes))
                
                if ($currentHash -ne $previousHash) {
                    Write-Host "New image detected in clipboard"
                    
                    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
                    $filename = "screenshot_$timestamp.png"
                    $filepath = Join-Path $SaveDirectory $filename
                    $image.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)
                    
                    $latestPath = Join-Path $SaveDirectory "latest.png"
                    if (Test-Path $latestPath) { Remove-Item $latestPath -Force }
                    Copy-Item $filepath $latestPath -Force
                    
                    # Create full path for WSL2 instead of using tilde
                    $wslPath = "/home/$WslUsername/.screenshots/$filename"
                    Start-Sleep -Milliseconds 1000
                    
                    if (Set-BothClipboards $wslPath) {
                        Write-Host "AUTO-SAVED: $filename"
                        Write-Host "Path ready for Ctrl+V: $wslPath"
                    }
                    
                    $previousHash = $currentHash
                }
                $image.Dispose()
            }
        }
        
# Function to process new screenshot file
function Process-NewScreenshot($sourceFile, $source = "Unknown") {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $filename = "screenshot_$timestamp.png"
    $filepath = Join-Path $SaveDirectory $filename
    
    # Copy to destination with new name
    Copy-Item $sourceFile $filepath -Force
    
    # Update latest.png
    $latestPath = Join-Path $SaveDirectory "latest.png"
    if (Test-Path $latestPath) { Remove-Item $latestPath -Force }
    Copy-Item $filepath $latestPath -Force
    
    # Create WSL path and set clipboard
    $wslPath = "/home/$WslUsername/.screenshots/$filename"
    if (Set-BothClipboards $wslPath) {
        Write-Host "NEW SCREENSHOT FROM $source`: $filename"
        Write-Host "Path ready for Ctrl+V: $wslPath"
    }
    return $filepath
}

        # Check for new files in monitored directories (ShareX, etc.)
        $currentTime = Get-Date
        foreach ($watchPath in $allWatchPaths) {
            if (Test-Path $watchPath) {
                $newFiles = Get-ChildItem $watchPath -File | Where-Object { 
                    ($_.Extension -match '\.(png|jpg|jpeg)$') -and 
                    ($_.LastWriteTime -gt $lastFileTime)
                }
                
                foreach ($file in $newFiles) {
                    $source = if ($watchPath -eq $ShareXPath) { "ShareX" } else { "Directory" }
                    Process-NewScreenshot $file.FullName $source
                }
            }
        }
        
        # Also check for new files in the save directory (for drag-drop screenshots)
        $newFiles = Get-ChildItem $SaveDirectory -Include "*.png","*.jpg","*.jpeg" -File | Where-Object { 
            $_.LastWriteTime -gt $lastFileTime -and $_.Name -ne "latest.png" -and $_.Name -notlike "screenshot_*"
        }
        
        if ($newFiles) {
            foreach ($file in $newFiles) {
                # Create full path for WSL2 instead of using tilde
                $wslPath = "/home/$WslUsername/.screenshots/$($file.Name)"
                Copy-Item $file.FullName (Join-Path $SaveDirectory "latest.png") -Force
                
                if (Set-BothClipboards $wslPath) {
                    Write-Host "NEW FILE DETECTED: $($file.Name)"
                    Write-Host "Path ready for Ctrl+V: $wslPath"
                }
            }
        }
        
        $lastFileTime = $currentTime
        
    } catch {
        Write-Warning "Error in main loop: $_"
        Start-Sleep -Milliseconds 1000
    }
}

# Cleanup watchers on exit
try {
    foreach ($watcher in $watchers) {
        if ($watcher) {
            $watcher.Dispose()
        }
    }
} catch {
    # Ignore cleanup errors
}
