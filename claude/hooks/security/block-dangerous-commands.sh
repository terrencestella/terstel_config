#!/usr/bin/env bash
# =============================================================================
# PreToolUse Hook: Block Dangerous Bash Commands
# =============================================================================
#
# This hook runs BEFORE bash commands execute.
# It blocks destructive patterns like rm -rf, force pushes, etc.
#
# Exit codes:
#   0 = Allow command
#   2 = Block command (stderr fed back to Claude)
#
# Usage:
#   Add to ~/.claude/settings.json:
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "~/.claude/hooks/block-dangerous-commands.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }
# =============================================================================

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract the command using jq
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$COMMAND" ]]; then
    exit 0  # No command, allow
fi

# -----------------------------------------------------------------------------
# Dangerous Patterns
#
# Note: destructive filesystem operations (rm -rf on root/home, mkfs, dd to
# disk devices) and sudo are no longer checked here. The sandbox's writable
# path allowlist covers the filesystem cases when it's on, but it has
# explicit escape hatches (settings.json's allowUnsandboxedCommands, and
# excludedCommands: ["docker"]) so it isn't a hard guarantee on its own -
# what actually covers these regardless of sandbox state is settings.json's
# permissions.deny (Bash(sudo:*)) and permissions.ask (Bash(rm:*)). This hook
# now only covers risks neither of those addresses: policy (force-push) and
# post-fetch code execution / exfiltration.
# -----------------------------------------------------------------------------

# Fork bomb. Not a filesystem or network operation, so the sandbox doesn't
# stop it - it's a resource-exhaustion attack via unbounded process creation.
if echo "$COMMAND" | grep -qE ':\(\)\s*\{.*:\s*\|\s*:.*&'; then
    echo "BLOCKED: Fork bomb pattern detected" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# git reset --hard / git clean -f: irreversible loss of uncommitted or
# untracked work. Unlike a bad commit (recoverable via reflog), there's no
# git-level undo for either of these.
if echo "$COMMAND" | grep -qE '\bgit\s+reset\s+--hard\b'; then
    echo "BLOCKED: git reset --hard discards uncommitted work irreversibly" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

if echo "$COMMAND" | grep -qE '\bgit\s+clean\s+-\w*f\w*\b'; then
    echo "BLOCKED: git clean -f deletes untracked files irreversibly" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Force push to main/master
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*(-f|--force)\s+.*(main|master|production|release)'; then
    echo "BLOCKED: Force push to protected branch" >&2
    echo "Command: $COMMAND" >&2
    echo "Tip: Create a PR instead of force pushing to main/master" >&2
    exit 2
fi

# chmod 777 (world-writable)
if echo "$COMMAND" | grep -qE 'chmod\s+(777|a\+rwx)'; then
    echo "BLOCKED: Setting world-writable permissions (777)" >&2
    echo "Command: $COMMAND" >&2
    echo "Tip: Use 755 for directories, 644 for files" >&2
    exit 2
fi

# Piping curl directly to shell (dangerous pattern)
if echo "$COMMAND" | grep -qE 'curl\s+.*\|\s*(ba)?sh'; then
    echo "BLOCKED: Piping curl output directly to shell" >&2
    echo "Command: $COMMAND" >&2
    echo "Tip: Download script first, review it, then execute" >&2
    exit 2
fi

# wget piped to shell
if echo "$COMMAND" | grep -qE 'wget\s+.*\|\s*(ba)?sh'; then
    echo "BLOCKED: Piping wget output directly to shell" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Commands that could exfiltrate data
if echo "$COMMAND" | grep -qE '(curl|wget|nc|netcat)\s+.*\.(env|pem|key|secret)'; then
    echo "BLOCKED: Command appears to exfiltrate sensitive files" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Docker commands that expose already-materialized .env values without ever
# reading the .env file itself - so the display-command check below can't
# catch them.
#   - `compose config` prints the fully interpolated compose file, values and
#     all - covers `docker compose config`, `docker-compose config`.
#   - `inspect` dumps a container's Config.Env, commonly populated from a
#     .env file at container start.
#   - `run`/`exec` (plain, or via `compose`/`docker-compose`) with `env` or
#     `printenv` as the container command prints the live environment - this
#     also covers `docker run --env-file .env ... env`, which puts .env's
#     values straight into the printed output without any compose layer.
if echo "$COMMAND" | grep -qE '\bdocker(-compose|\s+compose)\s+config\b' || \
   echo "$COMMAND" | grep -qE '\bdocker\s+(container\s+)?inspect\b' || \
   echo "$COMMAND" | grep -qE '\bdocker(-compose|\s+compose)?\s+(run|exec)\b.*\s(env|printenv)(\s|$)'; then
    echo "BLOCKED: Docker command exposes container environment variables" >&2
    echo "Command: $COMMAND" >&2
    echo "Tip: This can reveal secrets sourced from .env at container start" >&2
    exit 2
fi

# docker history --no-trunc reveals full, untruncated build-layer commands -
# including ARG/ENV values baked into an image at build time. Plain `docker
# history` truncates long values and is fine; --no-trunc is specifically what
# defeats that truncation, so it's the trigger rather than the base command.
if echo "$COMMAND" | grep -qE '\bdocker\s+history\b.*--no-trunc'; then
    echo "BLOCKED: docker history --no-trunc can reveal build-time secrets baked into image layers" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# docker cp pulling a sensitive file out of a container's filesystem. Source
# syntax is <container>:<path>, so this only matches the extraction
# direction, not copying a file into a container.
if echo "$COMMAND" | grep -qE '\bdocker\s+cp\s+\S+:\S*(\.env|/\.ssh/|secrets\.(yml|yaml))'; then
    echo "BLOCKED: docker cp appears to extract a sensitive file from a container" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Bare environment dump. Doesn't name any file, so nothing else here catches
# it - but if secrets were exported earlier in the session (e.g. via `set -a;
# source .env`), a plain env/printenv/set/export prints all of them.
if echo "$COMMAND" | grep -qE '\bprintenv\b' || \
   echo "$COMMAND" | grep -qE '(^|[;&|(]\s*)(env|set|export|declare\s+-x)\s*($|[;&|)])'; then
    echo "BLOCKED: Bare environment dump may expose secrets exported earlier in the session" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Sourcing .env loads it into the shell without "reading" it via any display
# command, so the check below can't catch it.
if echo "$COMMAND" | grep -qE '\bsource\s+[^|;]*\.env\b' || \
   echo "$COMMAND" | grep -qE '(^|[;&|]\s*)\.\s+[^|;]*\.env\b'; then
    echo "BLOCKED: Sourcing .env loads its secrets into the shell environment" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Printing a variable whose name looks like a secret. Matches on the variable
# NAME, independent of which file (if any) it originally came from.
if echo "$COMMAND" | grep -qEi '\b(echo|printf)\b[^;|&]*\$\{?[A-Za-z_]*(SECRET|KEY|TOKEN|PASSWORD|CREDENTIAL|API_KEY|AUTH|PRIVATE)[A-Za-z_]*\}?'; then
    echo "BLOCKED: Printing a variable that looks like a secret" >&2
    echo "Command: $COMMAND" >&2
    exit 2
fi

# Reading sensitive files via display commands.
#
# Template filenames are stripped out first. The pattern below is unanchored, so
# '.env' also matches inside '.env.example' - a file that exists precisely to be
# read. Scrubbing them keeps the rule strict for real secrets while letting the
# documented template through.
SCRUBBED=$(echo "$COMMAND" | sed -E 's#[^[:space:]]*\.(example|sample|template|dist)([^[:alnum:]]|$)# #g')

if echo "$SCRUBBED" | grep -qE '(cat|less|head|tail|more|bat|grep|rg|sed|awk|od|xxd|strings)\s+.*\.(env|ssh)' || \
   echo "$SCRUBBED" | grep -qE '(cat|less|head|tail|more|bat|grep|rg|sed|awk|od|xxd|strings)\s+.*secrets\.(yml|yaml)' || \
   echo "$SCRUBBED" | grep -qE '(cat|less|head|tail|more|bat|grep|rg|sed|awk|od|xxd|strings)\s+.*/\.ssh/'; then
    echo "BLOCKED: Reading sensitive file via display command" >&2
    echo "Command: $COMMAND" >&2
    echo "Tip: Use .env.example for variable names, never read sensitive files directly" >&2
    exit 2
fi

# -----------------------------------------------------------------------------
# Command is safe, allow it
# -----------------------------------------------------------------------------
exit 0
