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

Security hooks live in `claude/hooks/security/`:

| Hook | Purpose |
|---|---|
| `block-dangerous-commands.sh` | Blocks rm -rf on sensitive paths, force pushes to main, curl-to-shell, etc. |
| `block-secrets.py` | Prevents reading or writing .env, secrets, and SSH files |
| `block-npm.sh` | Intercepts npm/npx commands and redirects to bun equivalents |
