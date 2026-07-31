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
nametag -Name <name>
```

`<name>` is just a display name for the clone — it shows up in-game and in
the window title, and isn't tied to any Microsoft account. For example, to
give your sibling their own session:

```powershell
nametag -Name Sibling
```

This watches for Minecraft, clones it under the given name, and keeps
re-tagging window titles (e.g. `Minecraft - Sibling`) for as long as it
runs — re-tagging has to be continuous, since Minecraft resets its own title
once loading finishes. Leave it running for as long as you're playing.

Other flags:

| Flag               | Default | Description                                                                                                                     |
|--------------------|---------|-----------------------------------------------------------------------------------------------------------------------------------|
| `-PollSeconds <n>` | `1`     | How often to check for a new Minecraft launch, in seconds.                                                                     |
| `-ShowWindow`      | off     | Show the clone's console window (titled `Nametag - <name>`) instead of running it hidden — useful for troubleshooting a clone that fails to launch. |

`-Name` also defaults to `Clone` if omitted:

```powershell
nametag -Name Sibling -PollSeconds 2 -ShowWindow
```

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
  paths; just restart `nametag` to recapture.

## Credits

The process-command-line capture approach (finding the running Minecraft
process and reusing its launch command) is based on the macOS implementation
in [basbase/mc-login-cloner](https://github.com/basbase/mc-login-cloner/blob/master/src/mac.ts),
ported to Windows/PowerShell.
