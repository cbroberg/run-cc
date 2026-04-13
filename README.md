# run-cc

A pm2-ecosystem-style launcher that restores all your Claude Code sessions
into a fresh iTerm2 window with one command after a crash or reboot.

## Why

When working on multiple parallel projects it's normal to have 5-10 `cc`
sessions open at once, each in its own iTerm tab, each in the right directory,
each resumed from the right checkpoint. After a crash or reboot, rebuilding
that layout by hand is tedious. `run-cc` automates it.

## Install

```bash
git clone git@github.com:cbroberg/run-cc.git
cd run-cc
./install.sh
```

This copies `bin/run-cc` to `/usr/local/bin/` and seeds
`~/.config/run-cc/sessions.json` with an example config.

**Requirements:** macOS, iTerm2, `jq` (`brew install jq`), `ccb` on `$PATH`.

## Usage

```bash
run-cc                # Launch all sessions in a new iTerm2 window
run-cc list           # List configured sessions
run-cc add <name> <path> [<resume>]   # Add a session
run-cc remove <name>  # Remove a session
run-cc edit           # Open config in $EDITOR
run-cc path           # Print config file path
```

## Config

Lives at `~/.config/run-cc/sessions.json` (override with `$RUN_CC_CONFIG`):

```json
{
  "version": 1,
  "defaults": { "command": "ccb" },
  "sessions": [
    { "name": "cms", "path": "~/code/webhouse/cms", "resume": "f111-external-publishing" },
    { "name": "whop", "path": "~/code/webhouse/whop", "resume": null }
  ]
}
```

- **name** — iTerm tab title (keep short, <= 12 chars)
- **path** — working directory (`~` is expanded)
- **resume** — Claude Code session name to `--resume`, or `null` for a fresh session

## Tab naming

`run-cc` sets tab titles via iTerm2's AppleScript API. If the shell clobbers
them, uncheck **iTerm2 > Settings > Profiles > Terminal > Terminal may set
tab/window title**.

## Design

See [docs/PLAN.md](docs/PLAN.md) for full rationale and technical design.
