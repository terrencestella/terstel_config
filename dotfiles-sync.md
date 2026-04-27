# Dotfiles Sync Setup

Cross-machine config synchronization using Syncthing across three machines.

## Machines

| Machine | OS | Role |
|---|---|---|
| Mac (primary) | macOS | Primary (initiator) |
| Homeserver | Ubuntu | Follower |
| VPS | Ubuntu | Follower |

## What is synced

All config lives in `~/dotfiles/` which Syncthing keeps in sync. The actual config locations are symlinks pointing into this folder.

```
~/dotfiles/
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

`claude/plugins/` is excluded from Syncthing (see `.stignore`) — each machine manages its own plugin installations locally.

## How it works

Syncthing runs as a background service on all three machines and syncs `~/dotfiles/` bidirectionally. Any change on any machine propagates to the others automatically.

- macOS: managed via `brew services` (launchd)
- Linux: managed via `systemctl --user` with `loginctl enable-linger` so the service survives logout

Syncthing connectivity uses the built-in **relay server** fallback — no ports need to be opened in any firewall.

## Syncthing device IDs

Retrieve the device ID on any machine with:
```bash
syncthing cli show system | grep myID
```

## Cross-platform notes

The `.zshrc` uses an OS check to handle different plugin install paths:

```bash
if [[ "$(uname)" == "Darwin" ]]; then
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
else
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
```

macOS uses Homebrew. Ubuntu machines use apt-installed packages in `/usr/share/`.

## Git tracking

`~/dotfiles/` is also a git repository tracked at `github.com/terrencestella/terstel_config`. This provides version history on top of Syncthing's sync. Syncthing handles distribution across machines; git handles history and backup.

`.git/` is excluded from Syncthing — each machine has its own local git repo pointing to the same remote.

## What is NOT synced

- `~/.claude/projects/` — project-specific memory, stays local per machine
- `~/.claude/todos/` — no global todos, use per-project markdown files instead
- `~/.claude/plugins/` — each machine manages its own plugin installations
- `~/.zsh_history` — shell history stays local
- `~/.ssh/` — SSH keys never sync
- `.git/`, `README.md`, `dotfiles-sync.md` — excluded via `.stignore` (git/GitHub-only)

## Potential weak points

### Syncthing relay dependency
When devices can't connect directly, traffic routes through Syncthing's public relay servers. Sync may be delayed and depends on Syncthing's relay infrastructure being available.

### loginctl linger
If `loginctl enable-linger` is ever reset (e.g. after OS reinstall), Syncthing on Linux machines will stop running when no user is logged in. Sync silently stops until someone logs in.
Check with: `loginctl show-user <username> | grep Linger`

### Symlinks must be recreated on new machines
`~/dotfiles/` syncs automatically, but symlinks at `~/.zshrc`, `~/.gitconfig` etc. must be created manually on each new machine.

### hooks/.env contains credentials
`~/.claude/hooks/mobile-notify/.env` contains notification service credentials and is currently synced. Those credentials are present on all machines until the hook is removed.

### apt vs brew version mismatch
Linux machines use apt-installed Syncthing, macOS uses Homebrew. If the macOS config format ever exceeds what the apt version supports, sync on Linux will break with a config version error.
Fix: use the official Syncthing apt repository instead of distro packages.

## Adding a new machine

1. Install Syncthing (`brew install syncthing` or `apt install syncthing`)
2. Start it and get the device ID: `syncthing cli show system | grep myID`
3. On primary machine: add the new device and share the folder:
   ```bash
   syncthing cli config devices add --device-id <NEW-ID> --name <name>
   syncthing cli config folders dotfiles devices add --device-id <NEW-ID>
   ```
4. On new machine: add primary as device and accept the folder:
   ```bash
   syncthing cli config devices add --device-id <PRIMARY-ID> --name primary
   syncthing cli config folders add --id dotfiles --path ~/dotfiles
   syncthing cli config folders dotfiles devices add --device-id <PRIMARY-ID>
   ```
5. Enable linger (Linux only): `sudo loginctl enable-linger <username>`
6. Wait for sync, then create symlinks:
   ```bash
   ln -s ~/dotfiles/zshrc ~/.zshrc
   ln -s ~/dotfiles/gitconfig ~/.gitconfig
   ln -s ~/dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
   ln -s ~/dotfiles/claude/settings.json ~/.claude/settings.json
   ln -s ~/dotfiles/claude/hooks ~/.claude/hooks
   ln -s ~/dotfiles/claude/commands ~/.claude/commands
   ln -sf ~/dotfiles/ccstatusline/settings.json ~/.config/ccstatusline/settings.json
   ```
