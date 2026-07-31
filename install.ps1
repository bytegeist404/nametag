$ErrorActionPreference = 'Stop'

$RepoRawBase = "https://raw.githubusercontent.com/bytegeist404/nametag/main"
$InstallDir  = Join-Path $env:LOCALAPPDATA "Nametag"
$BinDir      = Join-Path $InstallDir "bin"

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

Write-Host "Downloading Nametag..."
Invoke-WebRequest -Uri "$RepoRawBase/nametag.ps1"   -OutFile (Join-Path $InstallDir "nametag.ps1")
Invoke-WebRequest -Uri "$RepoRawBase/uninstall.ps1" -OutFile (Join-Path $InstallDir "uninstall.ps1")

# CLI shim so `nametag` works from any terminal (cmd, PowerShell, Windows Terminal).
# .cmd is on PATHEXT everywhere, unlike .ps1, so this is the simplest way to
# make a bare `nametag <args>` command work without shell-specific profile edits.
@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$InstallDir\nametag.ps1" %*
"@ | Set-Content -Path (Join-Path $BinDir "nametag.cmd") -Encoding ASCII

# Add the bin dir to the User PATH (persisted; open a new terminal to pick it up).
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
    $newPath = if ($userPath) { "$userPath;$BinDir" } else { $BinDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}

# Register in Windows Settings > Apps > Installed apps with a working Uninstall button.
$RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Nametag"
New-Item -Path $RegKey -Force | Out-Null
Set-ItemProperty -Path $RegKey -Name "DisplayName"     -Value "Nametag"
Set-ItemProperty -Path $RegKey -Name "Publisher"       -Value "bytegeist404"
Set-ItemProperty -Path $RegKey -Name "DisplayVersion"  -Value "1.0.0"
Set-ItemProperty -Path $RegKey -Name "InstallLocation" -Value $InstallDir
Set-ItemProperty -Path $RegKey -Name "UninstallString" -Value "powershell -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""
Set-ItemProperty -Path $RegKey -Name "NoModify"        -Value 1 -Type DWord
Set-ItemProperty -Path $RegKey -Name "NoRepair"        -Value 1 -Type DWord

Write-Host ""
Write-Host "Nametag installed to $InstallDir"
Write-Host "Open a NEW terminal window and run: nametag -Name <YourAltName>"
Write-Host "To uninstall later: Settings > Apps > Installed apps > Nametag, or run 'nametag uninstall'."
