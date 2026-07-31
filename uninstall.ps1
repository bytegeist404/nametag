$ErrorActionPreference = 'Stop'

$InstallDir = $PSScriptRoot
$BinDir     = Join-Path $InstallDir "bin"
$RegKey     = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Nametag"

Write-Host "Uninstalling Nametag..."

# Remove the bin dir from the User PATH.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $parts = $userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $BinDir.TrimEnd('\')) }
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

# Remove the Windows Settings > Apps entry.
if (Test-Path $RegKey) {
    Remove-Item -Path $RegKey -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Removed from PATH and Windows Settings > Apps."

# This script is running from inside $InstallDir, so it can't delete that
# directory itself while it's still executing. Hand the cleanup off to a
# short-lived detached process that waits for this one to exit first.
$cleanupCmd = "Start-Sleep -Seconds 2; Remove-Item -Path '$InstallDir' -Recurse -Force -ErrorAction SilentlyContinue"
Start-Process -FilePath "powershell.exe" `
    -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cleanupCmd) `
    -WindowStyle Hidden

Write-Host "Nametag has been uninstalled."
