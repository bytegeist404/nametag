# Nametag

Clone a running vanilla Minecraft (Java Edition) instance under a different
username, so multiple people sharing one Microsoft account can join the same
LAN world without a "That name is already taken" error.

It works by grabbing the launch command of your already-running Minecraft
process, swapping `--username`, and starting a second instance from it —
each clone gets its own log/crash-report directory and an auto-tagged window
title so you can tell instances apart.

## Install

```powershell
irm https://raw.githubusercontent.com/bytegeist404/nametag/main/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Nametag`, adds `nametag` to your PATH, and
registers an entry under Windows Settings > Apps > Installed apps.

Open a **new** terminal window afterwards so the PATH change takes effect.

## Usage

Launch Minecraft normally via the vanilla launcher first, then:

```powershell
nametag once -Name ECHO              # clone the running instance once
nametag watch -Name ECHO             # keep watching; auto-clone new launches
nametag watch -Name ECHO -PollSeconds 2
```

`watch` also keeps re-tagging window titles (`Minecraft - ECHO`, etc.) for
as long as it runs, so both windows stay identifiable even after Minecraft
resets its own title on load.

## Uninstall

```powershell
nametag uninstall
```

Or: Settings > Apps > Installed apps > Nametag > Uninstall.

## Notes

- Each clone's launch command embeds your account's session token — it's
  short-lived (~24h) and machine-local; the generated `launch_*.cmd` files
  under `instances\` are not meant to be shared.
- A Minecraft client/Java runtime update can invalidate a clone's captured
  paths; just re-run `nametag once`/`watch` to recapture.
