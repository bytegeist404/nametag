[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'uninstall', 'help')]
    [string]$Command = 'run',

    [string]$Name = "Clone",

    [int]$PollSeconds = 1,

    [switch]$ShowWindow
)

$InstallRoot = $PSScriptRoot

Add-Type -Name Win32 -Namespace NametagNative -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool SetWindowText(IntPtr hWnd, string lpString);
"@ -ErrorAction SilentlyContinue

function Get-MinecraftProcesses {
    # Match on the vanilla client's actual entry point rather than guessing
    # from install/runtime folder names - this holds regardless of where the
    # launcher, Java runtime, or .minecraft folder happen to live.
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and
        $_.CommandLine -match '\bnet\.minecraft\.client\.main\.Main\b'
    }
}

function New-Clone {
    param($Proc, [string]$Name, [string]$InstallRoot, [switch]$ShowWindow)

    $cmd = $Proc.CommandLine
    $cmd = $cmd -replace '(-D[^ ]+=)\s+', '$1'
    $cmd = $cmd -replace '--username\s+\S+', "--username $Name"
    $cmd = $cmd -replace '\s*--quickPlayPath\s+\S+', ''

    # Tag the clone so no watcher (ours or a differently-named one) ever
    # treats this spawned clone as a source to clone again.
    $cmd = $cmd -replace '^("[^"]+")\s*', '$1 -Dcloner.marker=1 '

    # Give this name its own working directory. Log4j writes logs/ and
    # crash-reports/ as paths relative to the process's CWD (not --gameDir),
    # so instances sharing a CWD fight over the same log files. Wipe and
    # recreate it fresh on every (re)launch.
    $instanceDir = Join-Path $InstallRoot "instances\$Name"
    if (Test-Path $instanceDir) {
        Write-Host "Clearing previous '$Name' instance data in $instanceDir"
        Get-ChildItem -Path $instanceDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $instanceDir -Force | Out-Null
    }

    $launcher = Join-Path $instanceDir "launch_$Name.cmd"
    @"
@echo off
title Nametag - $Name
cd /d "$instanceDir"
$cmd
"@ | Set-Content -Path $launcher -Encoding ASCII

    $windowStyle = if ($ShowWindow) { 'Normal' } else { 'Hidden' }
    Start-Process -FilePath $launcher -WindowStyle $windowStyle
    return $launcher
}

function Set-InstanceTitle {
    param([int]$ProcessId, [string]$Label)
    $winProc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($winProc -and $winProc.MainWindowHandle -ne [IntPtr]::Zero) {
        [NametagNative.Win32]::SetWindowText($winProc.MainWindowHandle, "Minecraft - $Label") | Out-Null
        return $true
    }
    return $false
}

switch ($Command) {
    'run' {
        Write-Host "Watching for a vanilla Minecraft launch. Any instance found will be cloned as '$Name' (Ctrl+C to stop watching)."
        $clonedSources = @{}
        $titledLogged  = @{}

        while ($true) {
            foreach ($proc in (Get-MinecraftProcesses)) {
                if ($proc.CommandLine -notmatch '--username\s+(\S+)') { continue }
                $username = $matches[1]
                $isClone  = $proc.CommandLine -match '-Dcloner\.marker=1'
                $label    = if ($isClone) { $username } else { "$username (original)" }

                if (Set-InstanceTitle -ProcessId $proc.ProcessId -Label $label) {
                    if (-not $titledLogged.ContainsKey($proc.ProcessId)) {
                        $titledLogged[$proc.ProcessId] = $true
                        Write-Host "Window titled 'Minecraft - $label' (PID $($proc.ProcessId))"
                    }
                }

                if ($isClone) { continue }
                if ($clonedSources.ContainsKey($proc.ProcessId)) { continue }
                $clonedSources[$proc.ProcessId] = $true

                Write-Host "Found Minecraft running as '$username' (PID $($proc.ProcessId)) - launching a clone as '$Name'..."
                $launcher = New-Clone -Proc $proc -Name $Name -InstallRoot $InstallRoot -ShowWindow:$ShowWindow
                Write-Host "Clone '$Name' launched from $launcher"
            }

            Start-Sleep -Seconds $PollSeconds
        }
    }

    'uninstall' {
        & (Join-Path $InstallRoot "uninstall.ps1")
    }

    default {
        @"
Nametag - clone a running vanilla Minecraft instance under a different
username, so multiple people sharing one Microsoft account can join the
same LAN world without a "name already taken" collision.

Usage:
  nametag -Name <name> [-PollSeconds <n>] [-ShowWindow]   Watch for Minecraft, auto-clone it, and keep re-tagging window titles.
  nametag uninstall                                        Remove Nametag.

  -ShowWindow   Show the clone's console window (titled 'Nametag - <name>')
                instead of running it hidden. Useful for troubleshooting a
                clone that fails to launch.

Uninstall is also available from Windows Settings > Apps > Installed apps > Nametag.
"@ | Write-Host
    }
}
