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

This opens a new "Nametag" console window that watches for Minecraft, clones
it under the given name, and keeps re-tagging window titles (e.g.
`Minecraft - Sibling`) for as long as it runs — re-tagging has to be
continuous, since Minecraft resets its own title once loading finishes.
Leave it running for as long as you're playing.

Press Ctrl+C in the "Nametag" window to stop — it closes itself right away.
If something goes wrong instead (a clone fails to launch, or Nametag hits an
unexpected error), the window stays open and reports it, so you always get a
chance to read what happened before it disappears; a clone launch failure
also gets its captured output logged to `launcher-error.log` under
`instances\<name>\` for reference.

Flags:

| Flag               | Default | Description                                                  |
|--------------------|---------|---------------------------------------------------------------|
| `-Name <name>`     | `Clone` | Display name for the clone.                                  |
| `-PollSeconds <n>` | `1`     | How often to check for a new Minecraft launch, in seconds.   |

All together:

```powershell
nametag -Name Sibling -PollSeconds 2
```

If something looks wrong (a clone not getting tagged correctly, a process
not being picked up, etc.), add PowerShell's built-in `-Verbose` switch for
detailed diagnostics — captured command lines, per-poll process matches, and
so on. It's also saved to `%LOCALAPPDATA%\Nametag\nametag-verbose.log`, so
you can share the file directly instead of copy-pasting from the console:

```powershell
nametag -Name Sibling -Verbose
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
process and reusing its launch command) was created by
[basbase](https://github.com/basbase) for the macOS implementation in their
[mc-login-cloner](https://github.com/basbase/mc-login-cloner) project (see
[`src/mac.ts`](https://github.com/basbase/mc-login-cloner/blob/master/src/mac.ts)),
ported here to Windows/PowerShell.
