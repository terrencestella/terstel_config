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
│   └── hooks/              → ~/.claude/hooks/
└── ccstatusline/
    └── settings.json       → ~/.config/ccstatusline/settings.json
```

`claude/plugins/` is excluded from Syncthing (see `.stignore`) — each machine manages its own plugin installations locally. That local install state is kept in sync automatically by a hook; see [Plugin sync](#plugin-sync) below.

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
- `~/.claude/plugins/` — marketplace clones and plugin caches are machine-local (see [Plugin sync](#plugin-sync) — the *set* of installed plugins is kept in sync even though this directory isn't)
- `~/.zsh_history` — shell history stays local
- `~/.ssh/` — SSH keys never sync
- `.git/`, `README.md`, `dotfiles-sync.md` — excluded via `.stignore` (git/GitHub-only)

## Plugin sync

`~/.claude/plugins/` (marketplace clones, plugin caches, `known_marketplaces.json`) is machine-local and never synced — but `claude/settings.json` (which *is* synced) declares which marketplaces and plugins should exist, via `extraKnownMarketplaces` and `enabledPlugins`. `claude/hooks/sync-plugins.sh` reconciles the two, and is wired up as a `SessionStart` hook in `settings.json`, so it runs automatically every time `claude` starts on any machine:

1. For each marketplace in `extraKnownMarketplaces` not yet known locally (`claude plugin marketplace list`), run `claude plugin marketplace add <repo>` to clone it.
2. For each plugin in `enabledPlugins` not yet installed locally (`claude plugin list`), run `claude plugin install <plugin>@<marketplace>`.

Both steps are idempotent and non-fatal per-item — a failed add/install is logged and retried on the next session start rather than aborting the rest.

**Adding a new marketplace/plugin**: run `claude plugin marketplace add <owner>/<repo>` and `claude plugin install <plugin>@<marketplace>` on any one machine as normal. Both commands write to `extraKnownMarketplaces`/`enabledPlugins` in `settings.json`, which syncs via Syncthing; the hook then clones and installs on the other machines the next time `claude` starts there — no manual step needed on them.

**Requires** `jq` and the `claude` CLI on `PATH` (see [Adding a new machine](#adding-a-new-machine)) and outbound HTTPS to GitHub for the marketplace clones. If either prerequisite is missing on a machine, the hook fails silently on that machine and plugins stay out of sync there until it's fixed.

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

1. Install prerequisites: `brew install syncthing jq` or `apt install syncthing jq` (`jq` is required by the Claude plugin sync hook)
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
