#!/bin/bash
# Claude Code Mobile Notification Hook
# Sends push notifications via ntfy when Claude needs input from remote devices

# Exit early if not SSH connection
[[ -z "$SSH_CLIENT" ]] && exit 0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
source "$SCRIPT_DIR/ntfy.conf" 2>/dev/null || exit 0

# Source secrets from .env (REQUIRED)
source "$SCRIPT_DIR/.env" 2>/dev/null || exit 0

# Validate token is set
[[ -z "$NTFY_TOKEN" ]] && exit 0

# Detect device from tailscale status
CLIENT_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
DEVICE=$(tailscale status 2>/dev/null | grep "$CLIENT_IP" | awk '{print $1}')

# Determine ntfy topic based on device
if [[ "$DEVICE" == *"iphone"* ]]; then
    NTFY_TOPIC="cc-iphone"
elif [[ "$DEVICE" == *"ipad"* ]]; then
    NTFY_TOPIC="cc-ipad"
else
    exit 0
fi

# Check terminal idle time
TTY_PATH=$(tty 2>/dev/null)
if [[ -n "$TTY_PATH" && -e "$TTY_PATH" ]]; then
    CURRENT_TIME=$(date +%s)
    TTY_MTIME=$(stat -f %m "$TTY_PATH" 2>/dev/null)
    IDLE_SECONDS=$((CURRENT_TIME - TTY_MTIME))

    [[ "$IDLE_SECONDS" -lt "$IDLE_THRESHOLD" ]] && exit 0
fi

# Read hook input data from stdin
INPUT=$(cat)

# Parse hook event data
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Build notification based on event type
TITLE=""
MESSAGE=""
TAGS=""

case "$EVENT" in
  "PreToolUse")
    if [[ "$TOOL" == "AskUserQuestion" ]]; then
      QUESTION=$(echo "$INPUT" | jq -r '.tool_input.questions[0].question // "Question needed"' 2>/dev/null)
      TITLE="Claude needs input"
      MESSAGE="$QUESTION"
      TAGS="question,claude"
    fi
    ;;
  "PermissionRequest")
    OPERATION=$(echo "$INPUT" | jq -r '.tool_input.operation // "Permission needed"' 2>/dev/null)
    TITLE="Claude needs permission"
    MESSAGE="$OPERATION"
    TAGS="permission,claude"
    ;;
esac

# Send notification to ntfy if we have content
if [[ -n "$TITLE" && -n "$MESSAGE" ]]; then
  curl -sf \
    -H "Authorization: Bearer $NTFY_TOKEN" \
    -H "Title: $TITLE" \
    -H "Tags: $TAGS" \
    -H "Priority: high" \
    -d "$MESSAGE" \
    "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1
fi

exit 0
