[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('once', 'watch', 'uninstall', 'help')]
    [string]$Command = 'help',

    [string]$Name = "Clone",

    [int]$PollSeconds = 1
)

$InstallRoot = $PSScriptRoot

Add-Type -Name Win32 -Namespace NametagNative -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool SetWindowText(IntPtr hWnd, string lpString);
"@ -ErrorAction SilentlyContinue

function Get-MinecraftProcesses {
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and
        ($_.CommandLine -match '\\runtime\\java-runtime' -or $_.CommandLine -match '\\runtime\\jre') -and
        $_.CommandLine -match '\\\.minecraft\\bin\\'
    }
}

function New-Clone {
    param($Proc, [string]$Name, [string]$InstallRoot)

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
        Get-ChildItem -Path $instanceDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path $instanceDir -Force | Out-Null
    }

    $launcher = Join-Path $instanceDir "launch_$Name.cmd"
    @"
@echo off
cd /d "$instanceDir"
$cmd
"@ | Set-Content -Path $launcher -Encoding ASCII

    Start-Process -FilePath $launcher
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
    'once' {
        $source = Get-MinecraftProcesses |
            Where-Object { $_.CommandLine -notmatch '-Dcloner\.marker=1' } |
            Select-Object -First 1

        if (-not $source) {
            throw "No running (non-cloned) Minecraft instance found. Launch Minecraft via the vanilla launcher first."
        }

        $launcher = New-Clone -Proc $source -Name $Name -InstallRoot $InstallRoot
        Write-Host "Launched clone '$Name' from $launcher"
    }

    'watch' {
        Write-Host "Watching for Minecraft to launch as '$Name'... (Ctrl+C to stop)"
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
                        Write-Host "Tagged window for PID $($proc.ProcessId) as 'Minecraft - $label'"
                    }
                }

                if ($isClone) { continue }
                if ($clonedSources.ContainsKey($proc.ProcessId)) { continue }
                $clonedSources[$proc.ProcessId] = $true

                $launcher = New-Clone -Proc $proc -Name $Name -InstallRoot $InstallRoot
                Write-Host "Detected Minecraft (PID $($proc.ProcessId), '$username') - launched clone '$Name' from $launcher"
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
  nametag once  -Name <name>                     One-shot: clone the running instance now.
  nametag watch -Name <name> [-PollSeconds <n>]   Keep watching; auto-clone new launches and re-tag window titles.
  nametag uninstall                               Remove Nametag.

Uninstall is also available from Windows Settings > Apps > Installed apps > Nametag.
"@ | Write-Host
    }
}
