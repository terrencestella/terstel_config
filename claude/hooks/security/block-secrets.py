#!/usr/bin/env python3
"""
PreToolUse hook to block access to sensitive files.

This hook runs BEFORE Claude can read, edit, or write files.
Exit code 2 blocks the operation and feeds stderr back to Claude.

Usage:
  Add to ~/.claude/settings.json:
  {
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Read|Edit|Write",
          "hooks": [
            {
              "type": "command",
              "command": "python3 ~/.claude/hooks/security/block-secrets.py"
            }
          ]
        }
      ]
    }
  }

Why this matters:
  - CLAUDE.md rules are suggestions that Claude can override
  - This hook is deterministic enforcement - it ALWAYS runs
  - Even if Claude is "convinced" to read secrets, this blocks it
"""
import json
import sys
from pathlib import Path

# =============================================================================
# CONFIGURATION - Customize these patterns for your environment
# =============================================================================

# Exact filenames to block
#
# Note: .env*, secrets.yaml/yml, and .ssh paths are intentionally NOT listed
# here — Claude Code's native OS-level sandbox (read.denyOnly) and this
# repo's settings.json permissions.deny already hard-block those at two other
# layers. This file covers what those two layers don't.
SENSITIVE_FILENAMES = {
    # Secrets files
    'secrets.json',
    'secrets.toml',
    '.secrets',

    # Credentials
    'credentials.json',
    'credentials.yaml',
    'service-account.json',
    'service_account.json',
    
    # SSH keys
    'id_rsa',
    'id_rsa.pub',
    'id_ed25519',
    'id_ed25519.pub',
    'id_ecdsa',
    'id_dsa',
    'known_hosts',
    'authorized_keys',

    # Package manager auth
    '.npmrc',
    '.pypirc',
    '.yarnrc',

    # Git credentials
    '.git-credentials',
    '.gitconfig',  # Can contain credentials

    # Database
    '.pgpass',
    '.my.cnf',
    '.mongorc.js',

    # Shell/network auth
    '.envrc',        # direnv - loads secrets into the shell on cd
    '.netrc',        # per-host credentials for curl/ftp/etc
    '.vault-token',  # HashiCorp Vault token
}

# Multi-segment path endings to block. A basename-only check (like
# SENSITIVE_FILENAMES above) can never match these - "credentials" alone
# isn't the identifying part, the containing directory is - so they're
# matched against the full normalized path's ending instead.
SENSITIVE_PATH_SUFFIXES = {
    '.aws/credentials',
    '.aws/config',
    '.azure/credentials',
    '.docker/config.json',
    '.git/config',
    'gcloud/credentials.db',
    '.kube/config',
}

# File extensions to block
SENSITIVE_EXTENSIONS = {
    '.pem',      # Certificates/keys
    '.key',      # Private keys
    '.p12',      # PKCS#12 certificates
    '.pfx',      # Windows certificates
    '.jks',      # Java keystore
    '.keystore', # Generic keystore
    '.crt',      # Certificates (sometimes contain keys)
    '.cer',      # Certificates
}

# Patterns to match against the filename only (not the full path - matching
# the full path means any file living under a directory like secrets/ blocks
# reading this hook itself, since hooks/security/block-secrets.py contains
# 'secret').
SENSITIVE_PATH_PATTERNS = [
    'secret',
    'credential',
    'private_key',
    'privatekey',
]

# Template files are the documented way to share variable NAMES without values,
# so they are allowed even when they match the patterns above. Without this,
# '.env.' blocks .env.example, which defeats the purpose of having one.
SAFE_NAME_MARKERS = (
    '.example',
    '.sample',
    '.template',
    '.dist',
)

# =============================================================================
# HOOK LOGIC
# =============================================================================

def is_sensitive_file(file_path: str) -> tuple[bool, str]:
    """
    Check if a file path matches sensitive patterns.
    Returns (is_sensitive, reason).
    """
    if not file_path:
        return False, ""
    
    path = Path(file_path)
    file_name = path.name
    file_name_lower = file_name.lower()
    normalized = file_path.replace('\\', '/').lower().rstrip('/')

    # Templates first: .env.example and friends hold placeholders, never values.
    if any(marker in file_name_lower for marker in SAFE_NAME_MARKERS):
        return False, ""

    # Check exact filename match
    if file_name in SENSITIVE_FILENAMES:
        return True, f"'{file_name}' is a known sensitive file"

    # Check extension
    if path.suffix.lower() in SENSITIVE_EXTENSIONS:
        return True, f"'{path.suffix}' files may contain private keys or certificates"

    # Check multi-segment path endings
    for suffix in SENSITIVE_PATH_SUFFIXES:
        if normalized.endswith(suffix):
            return True, f"path ends with '{suffix}', a known sensitive location"

    # Check filename patterns
    for pattern in SENSITIVE_PATH_PATTERNS:
        if pattern in file_name_lower:
            return True, f"filename contains sensitive pattern '{pattern}'"

    return False, ""


def extract_file_path(data: dict) -> str:
    """
    Extract file path from tool input.
    Different tools use different parameter names.
    """
    tool_input = data.get('tool_input', {})
    
    # Try common parameter names
    for key in ['file_path', 'path', 'filename', 'file']:
        if key in tool_input:
            return tool_input[key]

    return ""


def main():
    try:
        # Read JSON input from stdin
        data = json.load(sys.stdin)
        
        # Get tool name for better error messages
        tool_name = data.get('tool_name', 'unknown')
        
        # Extract file path
        file_path = extract_file_path(data)
        
        if not file_path:
            # No file path found, allow the operation
            sys.exit(0)
        
        # Check if sensitive
        is_sensitive, reason = is_sensitive_file(file_path)
        
        if is_sensitive:
            # Construct error message that will be fed back to Claude
            error_msg = f"""
╔══════════════════════════════════════════════════════════════════╗
║                       SECURITY HOOK BLOCKED                       ║
╠══════════════════════════════════════════════════════════════════╣
║ Tool: {tool_name}
║ File: {file_path}
║ 
║ Reason: {reason}
║
║ This file likely contains secrets, credentials, or private keys
║ that should not be accessed programmatically.
║
║ Recommended actions:
║ • Use environment variables instead of reading .env directly
║ • Ask the user for specific (non-sensitive) information
║ • Reference .env.example for variable names only
║ • Store secrets in a proper secrets manager
╚══════════════════════════════════════════════════════════════════╝
""".strip()
            
            # Print to stderr (will be fed back to Claude)
            print(error_msg, file=sys.stderr)
            
            # Exit code 2 = block operation
            sys.exit(2)
        
        # File is not sensitive, allow operation
        sys.exit(0)
        
    except json.JSONDecodeError as e:
        # Invalid JSON input - log but allow (fail open)
        print(f"Hook warning: Invalid JSON input - {e}", file=sys.stderr)
        sys.exit(0)
        
    except Exception as e:
        # Unexpected error - log but allow (fail open)
        print(f"Hook error: {e}", file=sys.stderr)
        sys.exit(0)


if __name__ == '__main__':
    main()
