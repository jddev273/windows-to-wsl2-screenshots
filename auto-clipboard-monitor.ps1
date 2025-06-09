# True automatic clipboard monitor using Windows events
param(
    [string]$SaveDirectory = "~/.screenshots",
    [string]$WslDistro = "auto"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Convert the tilde path to WSL format
if ($SaveDirectory -eq "~/.screenshots") {
    # Try to auto-detect WSL distribution if auto mode is used
    if ($WslDistro -eq "auto") {
        # Get all WSL distributions excluding docker ones
        $WslDistros = @(wsl.exe -l -q 2>$null | Where-Object { 
            $_ -and $_.Trim() -ne "" -and $_ -notlike "*docker*" 
        } | ForEach-Object { 
            $_.Trim() -replace '\s+', '' -replace '\x00', ''
        })
        
        # Prefer Ubuntu-22.04 specifically
        $UbuntuDistro = $WslDistros | Where-Object { $_ -eq "Ubuntu-22.04" } | Select-Object -First 1
        
        # If not found, try any Ubuntu distribution but NOT Ubuntu-18.04
        if (-not $UbuntuDistro) {
            $UbuntuDistro = $WslDistros | Where-Object { $_ -like "*Ubuntu*" -and $_ -ne "Ubuntu-18.04" } | Select-Object -First 1
        }
        
        if ($UbuntuDistro) {
            $WslDistro = $UbuntuDistro
        } elseif ($WslDistros.Count -gt 0) {
            $WslDistro = $WslDistros[0]
        } else {
            # Hardcoded fallback
            $WslDistro = "Ubuntu-22.04"
            Write-Warning "Could not auto-detect WSL distribution, using fallback: $WslDistro"
        }
        
        Write-Host "Using WSL distribution: $WslDistro"
    }
    
    # Try multiple methods to get the WSL username
    $WslUsername = $null
    
    # Method 1: Direct whoami
    try {
        $WslUsername = wsl.exe -d $WslDistro whoami 2>$null
        if ($WslUsername) {
            $WslUsername = $WslUsername.Trim()
        }
    } catch {}
    
    # Method 2: Using bash -c
    if ([string]::IsNullOrWhiteSpace($WslUsername)) {
        try {
            $WslUsername = wsl.exe -d $WslDistro bash -c "whoami" 2>$null
            if ($WslUsername) {
                $WslUsername = $WslUsername.Trim()
            }
        } catch {}
    }
    
    # Method 3: Using sh -c
    if ([string]::IsNullOrWhiteSpace($WslUsername)) {
        try {
            $WslUsername = wsl.exe -d $WslDistro sh -c "whoami" 2>$null
            if ($WslUsername) {
                $WslUsername = $WslUsername.Trim()
            }
        } catch {}
    }
    
    # Method 4: Extract from home directory path
    if ([string]::IsNullOrWhiteSpace($WslUsername)) {
        try {
            $HomePath = wsl.exe -d $WslDistro sh -c "echo ~" 2>$null
            if ($HomePath -match "/home/([^/]+)") {
                $WslUsername = $Matches[1]
            }
        } catch {}
    }
    
    # Method 5: Hardcoded fallback based on Windows username
    if ([string]::IsNullOrWhiteSpace($WslUsername)) {
        # Try to use Windows username in lowercase as a last resort
        $WslUsername = $env:USERNAME.ToLower()
        Write-Warning "Could not detect WSL username, using Windows username as fallback: $WslUsername"
    }
    
    Write-Host "WSL Username: $WslUsername"
    $SaveDirectory = "\\wsl.localhost\$WslDistro\home\$WslUsername\.screenshots"
}

if (!(Test-Path $SaveDirectory)) {
    New-Item -ItemType Directory -Path $SaveDirectory -Force | Out-Null
}

Write-Host "WINDOWS-TO-WSL2 SCREENSHOT AUTOMATION STARTED"
Write-Host "Auto-saving images to: $SaveDirectory"
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
        
        # Also check for new files in the directory (for drag-drop screenshots)
        $currentTime = Get-Date
        $newFiles = Get-ChildItem $SaveDirectory -Filter "*.png" | Where-Object { 
            $_.LastWriteTime -gt $lastFileTime -and $_.Name -ne "latest.png" 
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
            $lastFileTime = $currentTime
        }
        
    } catch {
        Write-Warning "Error in main loop: $_"
        Start-Sleep -Milliseconds 1000
    }
}
