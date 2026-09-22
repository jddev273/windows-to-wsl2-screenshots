# Automatic Windows clipboard monitor for WSL2 screenshots.
param(
    [Parameter(Mandatory = $true)]
    [string]$SaveDirectory,

    [Parameter(Mandatory = $true)]
    [string]$WslSaveDirectory
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($SaveDirectory)) {
    throw "SaveDirectory must not be empty."
}
if ([string]::IsNullOrWhiteSpace($WslSaveDirectory)) {
    throw "WslSaveDirectory must not be empty."
}

$WslSaveDirectory = $WslSaveDirectory.TrimEnd('/')

if (!(Test-Path -LiteralPath $SaveDirectory)) {
    New-Item -ItemType Directory -Path $SaveDirectory -Force | Out-Null
}

$readyFile = Join-Path $SaveDirectory "monitor.ready"
$stopFile = Join-Path $SaveDirectory "monitor.stop"

# Clear stale control files from an earlier cleanly-terminated run, then publish
# readiness only after the Windows-side prerequisites and save directory exist.
Remove-Item -LiteralPath $readyFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $readyFile -Value ([System.Diagnostics.Process]::GetCurrentProcess().Id) -Encoding ASCII

Write-Host "WINDOWS-TO-WSL2 SCREENSHOT AUTOMATION STARTED"
Write-Host "Auto-saving images to: $SaveDirectory"
Write-Host "WSL paths use: $WslSaveDirectory"
Write-Host "Press Ctrl+C to stop"
Write-Host "Monitoring clipboard and directory changes..."

$previousHash = $null
$lastFileTime = Get-Date

function Set-ClipboardPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        [System.Windows.Forms.Clipboard]::SetText($Path)
        return $true
    } catch {
        Start-Sleep -Milliseconds 200
        try {
            [System.Windows.Forms.Clipboard]::SetText($Path)
            return $true
        } catch {
            Write-Warning "Could not set clipboard: $_"
            return $false
        }
    }
}

function Get-WslScreenshotPath {
    param([Parameter(Mandatory = $true)][string]$FileName)
    return "$WslSaveDirectory/$FileName"
}

try {
    while ($true) {
        if (Test-Path -LiteralPath $stopFile) {
            Write-Host "Stop requested by WSL"
            break
        }

        try {
            Start-Sleep -Milliseconds 500

            if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            $image = [System.Windows.Forms.Clipboard]::GetImage()
            if ($image) {
                try {
                    $ms = New-Object System.IO.MemoryStream
                    try {
                        $image.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                        $imageBytes = $ms.ToArray()
                    } finally {
                        $ms.Dispose()
                    }

                    $sha256 = [System.Security.Cryptography.SHA256]::Create()
                    try {
                        $currentHash = [System.BitConverter]::ToString($sha256.ComputeHash($imageBytes))
                    } finally {
                        $sha256.Dispose()
                    }

                    if ($currentHash -ne $previousHash) {
                        Write-Host "New image detected in clipboard"

                        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
                        $filename = "screenshot_$timestamp.png"
                        $filepath = Join-Path $SaveDirectory $filename
                        $image.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)

                        $latestPath = Join-Path $SaveDirectory "latest.png"
                        if (Test-Path -LiteralPath $latestPath) {
                            Remove-Item -LiteralPath $latestPath -Force
                        }
                        Copy-Item -LiteralPath $filepath -Destination $latestPath -Force

                        $wslPath = Get-WslScreenshotPath $filename
                        Start-Sleep -Milliseconds 1000

                        if (Set-ClipboardPath $wslPath) {
                            Write-Host "AUTO-SAVED: $filename"
                            Write-Host "Path ready for Ctrl+V: $wslPath"
                        }

                        $previousHash = $currentHash
                    }
                } finally {
                    $image.Dispose()
                }
            }
        }

        # Also detect PNG files added directly to the target directory.
        $currentTime = Get-Date
        $newFiles = Get-ChildItem -LiteralPath $SaveDirectory -Filter "*.png" | Where-Object {
            $_.LastWriteTime -gt $lastFileTime -and $_.Name -ne "latest.png"
        }

        if ($newFiles) {
            foreach ($file in $newFiles) {
                $wslPath = Get-WslScreenshotPath $file.Name
                Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $SaveDirectory "latest.png") -Force

                if (Set-ClipboardPath $wslPath) {
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
} finally {
    Remove-Item -LiteralPath $readyFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
}
