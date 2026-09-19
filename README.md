# terstel_config

Personal configuration files for shell, git, and Claude Code — synced across three machines via Syncthing and version-controlled here.

## What's in here

```
dotfiles/
├── zshrc                   → ~/.zshrc
├── gitconfig               → ~/.gitconfig
├── claude/
│   ├── CLAUDE.md           → ~/.claude/CLAUDE.md
│   ├── settings.json       → ~/.claude/settings.json
│   ├── hooks/              → ~/.claude/hooks/
│   └── commands/           → ~/.claude/commands/
└── ccstatusline/
    └── settings.json       → ~/.config/ccstatusline/settings.json
```

All active config lives in `~/dotfiles/`. The paths above are symlinks pointing here — Claude Code, git, and zsh read from their usual locations without knowing anything is different.

## How sync works

Syncthing keeps `~/dotfiles/` in sync bidirectionally across all machines. Git provides version history and a remote backup. They serve different purposes and are independent of each other.

- Syncthing syncs changes automatically in the background
- Git tracks history and allows recovery of previous states
- `.git/` is excluded from Syncthing — each machine maintains its own local repo

See [dotfiles-sync.md](dotfiles-sync.md) for the full setup, weak points, and instructions for adding a new machine.

## Machines

| Machine | OS |
|---|---|
| Mac (primary) | macOS |
| Homeserver | Ubuntu |
| VPS | Ubuntu |

## Claude Code hooks

Security hooks live in `claude/hooks/security/`. Destructive filesystem ops (`rm -rf` on root/home, `mkfs`, `dd` to disk devices, `sudo`) are handled by Claude Code's native OS-level sandbox instead of these hooks now:

| Hook | Purpose |
|---|---|
| `block-dangerous-commands.sh` | Blocks force-pushes to main, curl/wget-piped-to-shell, chmod 777, and reads of sensitive files via display commands |
| `block-secrets.py` | Blocks reading/writing sensitive filenames not already covered by the sandbox or `settings.json`'s permission denylist (credentials, private keys, cloud/package-manager auth) |
| `block-npm.sh` | Intercepts npm/npx commands and redirects to bun equivalents |

`claude/hooks/sync-plugins.sh` is not a security hook — see [Plugin sync](dotfiles-sync.md#plugin-sync) in dotfiles-sync.md.
