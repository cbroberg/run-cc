# run-cc — Claude Code Session Launcher for iTerm2

> A pm2-ecosystem-style launcher that restores all your Claude Code sessions
> into a fresh iTerm2 window with one command after a crash or reboot.

## Problem

Claude Code sessions are tied to a working directory and a session name
(`ccb --resume "<name>"`). When working on multiple parallel projects — CMS,
WHop, music-quiz, CPM, cronjobs — it's normal to have 5–10 `cc` sessions open
at once, each in its own iTerm tab, each in the right directory, each resumed
from the right checkpoint.

After a crash or reboot, rebuilding that layout by hand is tedious and
error-prone: wrong path, forgot a session, forgot which session belonged to
which project. iTerm2's Window Arrangements restore layout + working directory
but do **not** re-run commands, so `ccb --resume` is still manual per tab.

## Solution

A single JSON config file lists the sessions you normally run. A `run-cc`
shell command reads the config and uses iTerm2's AppleScript API to:

1. Open a fresh iTerm2 window
2. Create one tab per session entry
3. Name each tab
4. `cd` to the right path
5. Run `ccb --resume "<name>"` (with a fallback to plain `ccb` if the session
   can't be resumed)

Config lives at `~/.config/run-cc/sessions.json` and can be hand-edited in
VS Code or mutated by `cc` itself via `jq`. A small `run-cc add|remove|list`
CLI sits on top for convenience.

### Why iTerm2 AppleScript (not keystroke injection)

iTerm2 exposes a first-class AppleScript API with `create tab`, `write text`,
and `set name to`. This means:

- **No Accessibility permission needed** — we talk to iTerm2 directly, not via
  `System Events` keystroke synthesis.
- **No timing `sleep`s** — `write text` is synchronous.
- **Keyboard-layout immune** — `write text` sends raw text, not keystrokes, so
  Danish layout is irrelevant.
- **Real tab naming** via `set name to "..."` instead of OSC escape hacks.

This is objectively cleaner than the equivalent Ghostty approach, which has to
go through `osascript → System Events → keystroke` because Ghostty has no
native CLI for "open new tab in existing window" yet
([ghostty#12136](https://github.com/ghostty-org/ghostty/issues/12136)).

## Technical Design

### 1. Repository layout

```
run-cc/
├── README.md                 # User-facing docs
├── PLAN.md                   # This file
├── LICENSE                   # MIT
├── bin/
│   └── run-cc                # Main bash entrypoint (executable)
├── lib/
│   └── launch.applescript.sh # AppleScript builder (sourced by bin/run-cc)
├── examples/
│   └── sessions.json         # Example config shipped in the repo
└── install.sh                # Copies bin/run-cc to /usr/local/bin, sets up config dir
```

Keeping the AppleScript builder in `lib/` (rather than inlining it in the
entrypoint) makes it easy to diff, test, and later swap for the Python API
version without touching the CLI surface.

### 2. Config schema

File: `~/.config/run-cc/sessions.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "version": 1,
  "defaults": {
    "command": "ccb"
  },
  "sessions": [
    {
      "name": "cms",
      "path": "~/code/webhouse/cms",
      "resume": "f111-external-publishing"
    },
    {
      "name": "whop",
      "path": "~/code/webhouse/whop",
      "resume": "whop-f1-foundation"
    },
    {
      "name": "music-quiz",
      "path": "~/code/webhouse/apple-music-mcp",
      "resume": "quiz-monorepo-migration"
    },
    {
      "name": "cpm",
      "path": "~/code/webhouse/cpm",
      "resume": null
    }
  ]
}
```

Field semantics:

- `name` *(required)* — used as the iTerm tab title. Should be short (≤ 12 chars)
  so multiple tabs fit in the tab bar.
- `path` *(required)* — working directory. `~` is expanded. Relative paths are
  rejected with a clear error.
- `resume` *(optional, nullable)* — Claude Code session name to resume. `null`
  or omitted means: start a fresh `ccb` session in this directory.
- `defaults.command` *(optional)* — the base command, defaults to `ccb`. Lets
  you swap to plain `claude` or a wrapper if you want. Per-session override via
  a `command` field is allowed but not encouraged.

### 3. The launcher script

File: `bin/run-cc`

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${RUN_CC_CONFIG:-$HOME/.config/run-cc/sessions.json}"
SUBCMD="${1:-launch}"

usage() {
  cat <<EOF
run-cc — Claude Code session launcher for iTerm2

Usage:
  run-cc [launch]                       Launch all sessions from config
  run-cc list                           List configured sessions
  run-cc add <name> <path> [<resume>]   Append a new session to config
  run-cc remove <name>                  Remove a session by name
  run-cc edit                           Open config in \$EDITOR
  run-cc path                           Print config file path

Config: \$RUN_CC_CONFIG or ~/.config/run-cc/sessions.json
EOF
}

require_jq() {
  command -v jq >/dev/null || {
    echo "run-cc: jq required (brew install jq)" >&2
    exit 1
  }
}

require_config() {
  if [[ ! -f "$CONFIG" ]]; then
    echo "run-cc: no config at $CONFIG" >&2
    echo "run 'run-cc add <name> <path> [<resume>]' to create one" >&2
    exit 1
  fi
}

ensure_config_dir() {
  mkdir -p "$(dirname "$CONFIG")"
  if [[ ! -f "$CONFIG" ]]; then
    echo '{"version":1,"defaults":{"command":"ccb"},"sessions":[]}' > "$CONFIG"
  fi
}

cmd_launch() {
  require_jq
  require_config

  local count
  count=$(jq '.sessions | length' "$CONFIG")
  if [[ "$count" -eq 0 ]]; then
    echo "run-cc: no sessions in config"
    exit 0
  fi

  local base_cmd
  base_cmd=$(jq -r '.defaults.command // "ccb"' "$CONFIG")

  # Build the AppleScript program in a variable, then hand it to osascript once.
  local script='tell application "iTerm2"
  activate
  set newWindow to (create window with default profile)
'

  local i name path resume cmd cmd_esc
  for i in $(seq 0 $((count - 1))); do
    name=$(jq -r   ".sessions[$i].name"           "$CONFIG")
    path=$(jq -r   ".sessions[$i].path"           "$CONFIG")
    resume=$(jq -r ".sessions[$i].resume // \"\"" "$CONFIG")
    path="${path/#\~/$HOME}"

    if [[ -n "$resume" ]]; then
      cmd="cd '$path' && $base_cmd --resume '$resume' || $base_cmd"
    else
      cmd="cd '$path' && $base_cmd"
    fi

    # Escape double quotes and backslashes for AppleScript string literal
    cmd_esc="${cmd//\\/\\\\}"
    cmd_esc="${cmd_esc//\"/\\\"}"
    name_esc="${name//\"/\\\"}"

    if [[ "$i" -eq 0 ]]; then
      script+="
  tell current session of newWindow
    set name to \"$name_esc\"
    write text \"$cmd_esc\"
  end tell"
    else
      script+="
  tell newWindow
    create tab with default profile
  end tell
  tell current session of newWindow
    set name to \"$name_esc\"
    write text \"$cmd_esc\"
  end tell"
    fi
  done

  script+='
end tell'

  osascript -e "$script" >/dev/null
  echo "run-cc: launched $count session(s) in iTerm2"
}

cmd_list() {
  require_jq
  require_config
  jq -r '.sessions[] | "\(.name)\t\(.path)\t\(.resume // "—")"' "$CONFIG" \
    | column -t -s $'\t' -N NAME,PATH,RESUME
}

cmd_add() {
  require_jq
  ensure_config_dir
  local name="${2:-}" path="${3:-}" resume="${4:-}"
  if [[ -z "$name" || -z "$path" ]]; then
    echo "run-cc: usage: run-cc add <name> <path> [<resume>]" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  if [[ -n "$resume" ]]; then
    jq --arg n "$name" --arg p "$path" --arg r "$resume" \
      '.sessions += [{name:$n, path:$p, resume:$r}]' "$CONFIG" > "$tmp"
  else
    jq --arg n "$name" --arg p "$path" \
      '.sessions += [{name:$n, path:$p, resume:null}]' "$CONFIG" > "$tmp"
  fi
  mv "$tmp" "$CONFIG"
  echo "run-cc: added '$name'"
}

cmd_remove() {
  require_jq
  require_config
  local name="${2:-}"
  [[ -z "$name" ]] && { echo "run-cc: usage: run-cc remove <name>" >&2; exit 1; }
  local tmp
  tmp=$(mktemp)
  jq --arg n "$name" '.sessions |= map(select(.name != $n))' "$CONFIG" > "$tmp"
  mv "$tmp" "$CONFIG"
  echo "run-cc: removed '$name'"
}

cmd_edit() {
  ensure_config_dir
  "${EDITOR:-code}" "$CONFIG"
}

cmd_path() {
  echo "$CONFIG"
}

case "$SUBCMD" in
  launch|"")    cmd_launch       ;;
  list)         cmd_list         ;;
  add)          cmd_add "$@"     ;;
  remove|rm)    cmd_remove "$@"  ;;
  edit)         cmd_edit         ;;
  path)         cmd_path         ;;
  -h|--help|help) usage          ;;
  *)            usage; exit 1    ;;
esac
```

### 4. Tab naming — how it actually works

Yes, the script names each tab as it's spawned. The relevant line is:

```applescript
tell current session of newWindow
  set name to "cms"
  write text "cd '/Users/cb/code/webhouse/cms' && ccb --resume 'f111'"
end tell
```

In iTerm2, `set name to "..."` on a **session** sets the tab title immediately
and persistently — it is not overwritten by shell prompt updates unless you
have a profile setting that re-exports `PROMPT_COMMAND` to emit OSC 0/2
sequences. If you ever see the name get clobbered by the shell, the fix is:

**iTerm2 → Settings → Profiles → Terminal → Terminal may set tab/window title** → **uncheck**

With that unchecked, the name you set via AppleScript is sticky for the life
of the tab.

If you'd rather keep shell-driven titles globally but still have `run-cc`
override them, use the profile-level approach: create a dedicated "run-cc"
iTerm2 profile with that checkbox unchecked, and change the launcher to use
`(create window with profile "run-cc")` instead of `default profile`.

### 5. Installation script

File: `install.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_DIR/bin/run-cc"
BIN_DST="/usr/local/bin/run-cc"
CONFIG_DIR="$HOME/.config/run-cc"
CONFIG_FILE="$CONFIG_DIR/sessions.json"

command -v jq >/dev/null || {
  echo "run-cc: jq is required. Install with: brew install jq" >&2
  exit 1
}

# Check iTerm2 is installed
if [[ ! -d "/Applications/iTerm.app" ]]; then
  echo "run-cc: iTerm2 not found at /Applications/iTerm.app" >&2
  echo "Install iTerm2 first: https://iterm2.com" >&2
  exit 1
fi

# Install binary
if [[ -w "/usr/local/bin" ]]; then
  install -m 0755 "$BIN_SRC" "$BIN_DST"
else
  sudo install -m 0755 "$BIN_SRC" "$BIN_DST"
fi
echo "installed: $BIN_DST"

# Create config dir + seed config if missing
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$REPO_DIR/examples/sessions.json" "$CONFIG_FILE"
  echo "created: $CONFIG_FILE (example config — edit with 'run-cc edit')"
else
  echo "kept:    $CONFIG_FILE (already exists)"
fi

echo ""
echo "done. try: run-cc list"
```

## Implementation Steps

Phase 1 — **bootstrap** *(the part cc does)*

1. Create repo structure as listed above.
2. Write `bin/run-cc` verbatim from §3.
3. Write `install.sh` from §5.
4. Write `examples/sessions.json` with 2–3 placeholder entries.
5. Write `README.md` with: one-paragraph overview, install instructions
   (`./install.sh`), usage (`run-cc`, `run-cc add`, `run-cc list`, etc.),
   and a link to `PLAN.md` for rationale.
6. `chmod +x bin/run-cc install.sh`.
7. Initial commit, push to `github.com/cbroberg/run-cc` (private).

Phase 2 — **first real use**

1. Run `./install.sh`.
2. `run-cc edit` — populate with the actual cc sessions in rotation right now
   (cms, whop, music-quiz, cpm, cronjobs, …).
3. `run-cc` — verify all tabs spawn, are named correctly, and land in the
   right directory with `ccb --resume` running.
4. If tab titles get clobbered by the shell, apply the profile fix from §4.

Phase 3 — **nice-to-haves** *(optional, later)*

- `run-cc doctor` — checks iTerm2 is installed, `ccb` is on PATH, config is
  valid JSON, and every `path` exists.
- `run-cc save` — introspect the currently-open iTerm2 window and dump its
  tabs back to `sessions.json` (AppleScript can read `name` and the tab's
  working directory, so this is feasible). Effectively "pm2 save" for your
  terminal layout.
- Per-session `profile` field to launch specific tabs with specific iTerm2
  profiles (different colors for prod vs dev, for example).
- A `groups` concept — `run-cc launch --group cms` to launch only a subset.

## Dependencies

- macOS (AppleScript-only — no Linux path)
- iTerm2
- `jq` (`brew install jq`)
- `ccb` (your existing Claude Code wrapper) on `$PATH`

Nothing else. No Python, no Node, no Homebrew formula required.

## Open Questions

1. **Should `run-cc` reuse an existing iTerm window if one is open?** Current
   design always spawns a fresh window, which is simpler and safer but means
   running `run-cc` twice gives you two windows. For the crash-recovery use
   case this is fine. Revisit if it becomes annoying.
2. **How should `ccb --resume` failures surface?** The `|| $base_cmd` fallback
   means a missing session silently becomes a fresh `ccb`. That's probably the
   right behavior, but maybe we want a 1-second banner printed to the tab
   ("session 'x' not found, starting fresh") so it's not invisible.
3. **Should `sessions.json` be checked into a dotfiles repo?** Personal-ish,
   but also project-list-shaped. Probably yes, with the actual session *names*
   being the only thing that drifts. Not a concern for v1.

## Effort Estimate

- Phase 1 (bootstrap): **30–45 min** for cc — straight transcription from this
  doc, no real decisions to make.
- Phase 2 (first real use + tab-title fix if needed): **10 min** manual.
- Phase 3: deferred.

Total to working state: **~1 hour**.
