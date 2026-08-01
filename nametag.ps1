[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'uninstall', 'help')]
    [string]$Command = 'run',

    [string]$Name = "Clone",

    [int]$PollSeconds = 1
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
    param($Proc, [string]$Name, [string]$InstallRoot)

    Write-Verbose "Captured command line for PID $($Proc.ProcessId): $($Proc.CommandLine)"

    $cmd = $Proc.CommandLine
    $cmd = $cmd -replace '(-D[^ ]+=)\s+', '$1'
    $cmd = $cmd -replace '--username\s+\S+', "--username $Name"
    $cmd = $cmd -replace '\s*--quickPlayPath\s+\S+', ''

    # Tag the clone so no watcher (ours or a differently-named one) ever
    # treats this spawned clone as a source to clone again. Anchored to the
    # main class (guaranteed present - it's what Get-MinecraftProcesses
    # matched on) rather than the leading executable token: that token is
    # only quoted when the path happens to contain a space, so anchoring
    # there silently dropped the marker on installs where it didn't -
    # producing an untagged clone that looked like a fresh original and
    # got cloned again, and again, and again.
    $cmd = $cmd -replace '\bnet\.minecraft\.client\.main\.Main\b', '-Dcloner.marker=1 $0'

    if ($cmd -notmatch '-Dcloner\.marker=1') {
        Write-Warning "Clone '$Name' could not be tagged (net.minecraft.client.main.Main wasn't found in the captured command line). It will look like a fresh original and may get cloned again in a loop. Run nametag with -Verbose to see the captured command line."
    }

    Write-Verbose "Clone command line: $cmd"

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
cd /d "$instanceDir"
$cmd
"@ | Set-Content -Path $launcher -Encoding ASCII

    # Clones always run hidden. If one fails to launch, the run loop detects
    # it (the wrapper process below exits almost immediately) and reports it
    # in the watcher window itself using this captured stderr - see the
    # $pendingClones handling in the 'run' case. Minecraft's own logging goes
    # to logs/latest.log via Log4j, not stdout, so stderr alone is what
    # launch-time failures (bad classpath, missing jar, etc.) show up in.
    $errorLog = Join-Path $instanceDir "launcher-error.log"
    $proc = Start-Process -FilePath $launcher -WindowStyle Hidden -RedirectStandardError $errorLog -PassThru
    return [pscustomobject]@{
        Launcher  = $launcher
        ProcessId = $proc.Id
        ErrorLog  = $errorLog
    }
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
        # -Verbose sets $VerbosePreference to 'Continue' for this run; piggyback
        # on that to also save everything (Write-Host/-Verbose/-Warning alike)
        # to a plain text file, so a -Verbose session can be shared as-is
        # instead of having to be copy-pasted out of the console.
        $transcriptPath = $null
        if ($VerbosePreference -eq 'Continue') {
            $transcriptPath = Join-Path $InstallRoot "nametag-verbose.log"
            Start-Transcript -Path $transcriptPath | Out-Null
            Write-Host "Saving verbose output to $transcriptPath"
        }

        Write-Host "Watching for a vanilla Minecraft launch. Any instance found will be cloned as '$Name' (Ctrl+C to stop watching)."
        $clonedSources  = @{}
        $titledLogged   = @{}
        $pendingClones  = @{}
        $failureWindow  = [TimeSpan]::FromSeconds(10)

        try {
            while ($true) {
                $processes = @(Get-MinecraftProcesses)
                Write-Verbose "Poll: found $($processes.Count) Minecraft process(es)."

                foreach ($proc in $processes) {
                    Write-Verbose "PID $($proc.ProcessId): $($proc.CommandLine)"

                    if ($proc.CommandLine -notmatch '--username\s+(\S+)') {
                        Write-Verbose "PID $($proc.ProcessId): no --username found, skipping."
                        continue
                    }
                    $username = $matches[1]
                    $isClone  = $proc.CommandLine -match '-Dcloner\.marker=1'
                    $label    = if ($isClone) { $username } else { "$username (original)" }
                    Write-Verbose "PID $($proc.ProcessId): username='$username' isClone=$isClone"

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
                    $clone = New-Clone -Proc $proc -Name $Name -InstallRoot $InstallRoot
                    Write-Host "Clone '$Name' launched from $($clone.Launcher)"
                    $pendingClones[$clone.ProcessId] = [pscustomobject]@{
                        Name       = $Name
                        ErrorLog   = $clone.ErrorLog
                        LaunchedAt = Get-Date
                    }
                }

                # A clone's wrapper process is just cmd.exe running the java
                # command in the foreground, so it stays alive exactly as long
                # as the clone does. If it exits within $failureWindow of being
                # launched, that's a startup failure (bad classpath, missing
                # jar, etc. surface in well under that); anything later is just
                # the player quitting normally.
                foreach ($wrapperPid in @($pendingClones.Keys)) {
                    $entry   = $pendingClones[$wrapperPid]
                    $elapsed = (Get-Date) - $entry.LaunchedAt
                    $wrapper = Get-Process -Id $wrapperPid -ErrorAction SilentlyContinue

                    if (-not $wrapper -or $wrapper.HasExited) {
                        if ($elapsed -lt $failureWindow) {
                            Write-Host ""
                            Write-Host "Clone '$($entry.Name)' failed to launch (exited after $([int]$elapsed.TotalSeconds)s)." -ForegroundColor Red
                            if (Test-Path $entry.ErrorLog) {
                                $errText = (Get-Content -Path $entry.ErrorLog -Raw -ErrorAction SilentlyContinue)
                                if ($errText) { Write-Host $errText.Trim() -ForegroundColor DarkYellow }
                            }
                            Read-Host "Press Enter to continue watching" | Out-Null
                        }
                        $pendingClones.Remove($wrapperPid)
                    } elseif ($elapsed -ge $failureWindow) {
                        $pendingClones.Remove($wrapperPid)
                    }
                }

                Start-Sleep -Seconds $PollSeconds
            }
        } catch [System.Management.Automation.PipelineStoppedException] {
            # Ctrl+C - a clean, requested stop. Just let the window close.
        } catch {
            Write-Host ""
            Write-Host "Nametag stopped unexpectedly: $_" -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
            Read-Host "Press Enter to close this window" | Out-Null
        } finally {
            if ($transcriptPath) { Stop-Transcript | Out-Null }
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
  nametag -Name <name> [-PollSeconds <n>] [-Verbose]   Watch for Minecraft, auto-clone it, and keep re-tagging window titles.
  nametag uninstall                                     Remove Nametag.

If a clone fails to launch, Nametag reports it right in this window and
waits for a keypress before continuing to watch. Add -Verbose for detailed
diagnostics (captured command lines, per-poll process matches, etc.) if
something looks wrong - it's also saved to nametag-verbose.log so it can be
shared without copy-pasting from the console.

Uninstall is also available from Windows Settings > Apps > Installed apps > Nametag.
"@ | Write-Host
    }
}
