#!/bin/bash

# Read JSON input from stdin first (before any redirects)
input=$(cat)

# Detect terminal type for optimization
IS_VSCODE=false
[[ "$TERM_PROGRAM" == "vscode" ]] && IS_VSCODE=true

# Redirect all errors to /dev/null to prevent stderr pollution
exec 2>/dev/null

# Exit with success even if we output nothing
trap 'exit 0' EXIT

# Cache settings
CACHE_FILE="$HOME/.claude/.statusline_cache"
CACHE_TTL=300  # 5 minutes in seconds

# Check if jq exists, fallback to basic parsing
if command -v jq >/dev/null 2>&1; then
    # Use system jq
    jq_cmd="jq"
else
    # Fallback to basic parsing
    jq_cmd=""
fi

# Function to extract JSON values
extract_value() {
    local path="$1"
    if [[ -n "$jq_cmd" ]]; then
        echo "$input" | "$jq_cmd" -r "$path // empty" 2>/dev/null
    else
        # Basic fallback parsing
        local key="${path##*.}"
        echo "$input" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1
    fi
}

# Function to extract JSON numeric values
extract_number() {
    local path="$1"
    if [[ -n "$jq_cmd" ]]; then
        echo "$input" | "$jq_cmd" "$path // null" 2>/dev/null
    else
        # Basic fallback parsing for numbers
        local key="${path##*.}"
        echo "$input" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]*" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/' | head -1
    fi
}

# Cache functions
read_cache() {
    local dir="$1"
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    # Read cache and check if it matches current directory
    local cache_content=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
    if [[ -z "$cache_content" ]]; then
        return 1
    fi

    local cache_dir=$(echo "$cache_content" | grep "^DIR=" | cut -d'=' -f2-)
    local cache_time=$(echo "$cache_content" | grep "^TIME=" | cut -d'=' -f2)

    if [[ "$cache_dir" != "$dir" ]]; then
        return 1
    fi

    # Check if cache is still valid
    local current_time=$(date +%s 2>/dev/null || echo "0")
    if [[ "$current_time" == "0" ]] || [[ -z "$cache_time" ]]; then
        return 1
    fi

    local age=$((current_time - cache_time))

    if [[ $age -gt $CACHE_TTL ]]; then
        return 1
    fi

    # Return cached values
    echo "$cache_content"
    return 0
}

write_cache() {
    local dir="$1"
    local branch="$2"
    local current_time=$(date +%s 2>/dev/null || echo "0")

    if [[ "$current_time" == "0" ]]; then
        return 1
    fi

    cat > "$CACHE_FILE" 2>/dev/null <<EOF
DIR=$dir
TIME=$current_time
BRANCH=$branch
EOF
    return 0
}

# Extract values using the fallback-capable function
model_name=$(extract_value ".model.display_name")
current_dir=$(extract_value ".workspace.current_dir")
project_dir=$(extract_value ".workspace.project_dir")

# Get project/directory name
if [[ -n "$project_dir" ]]; then
    # Convert Windows path to Unix-style for Git Bash
    project_dir=$(echo "$project_dir" | sed 's|\\|/|g')
    project_name=$(basename "$project_dir")
elif [[ -n "$current_dir" ]]; then
    current_dir=$(echo "$current_dir" | sed 's|\\|/|g')
    project_name=$(basename "$current_dir")
else
    project_name="no-project"
fi

# Get git branch with caching
git_branch=""
if [[ -n "$current_dir" ]] && [[ -d "$current_dir" ]]; then
    # Try to read from cache first
    cache_data=$(read_cache "$current_dir")
    if [[ $? -eq 0 ]]; then
        # Use cached data
        git_branch=$(echo "$cache_data" | grep "^BRANCH=" | cut -d'=' -f2-)
    else
        # Cache miss or stale - run git commands
        if [[ -d "$current_dir/.git" ]] || (cd "$current_dir" && git rev-parse --git-dir >/dev/null 2>&1); then
            branch=$(cd "$current_dir" && git branch --show-current 2>&1 | grep -v "^fatal" | head -1)
            if [[ -n "$branch" ]]; then
                git_branch="$branch"
                # Write to cache (fail silently if it doesn't work)
                write_cache "$current_dir" "$git_branch" 2>/dev/null || true
            fi
        fi
    fi
fi

# Calculate context window usage using pre-calculated percentages
progress_bar=""
token_usage=""

if [[ -n "$jq_cmd" ]]; then
    used_pct=$(echo "$input" | "$jq_cmd" -r '.context_window.used_percentage // empty' 2>/dev/null)

    if [[ -n "$used_pct" ]] && [[ "$used_pct" != "null" ]]; then
        # Convert to integer for progress bar
        pct=$(printf "%.0f" "$used_pct" 2>/dev/null)

        if [[ -n "$pct" ]] && [[ "$pct" =~ ^[0-9]+$ ]]; then
            # Generate progress bar (10 characters)
            filled=$((pct / 10))
            empty=$((10 - filled))
            bar="["
            for ((i=0; i<filled; i++)); do bar+="="; done
            for ((i=0; i<empty; i++)); do bar+="-"; done
            bar+="]"

            # Apply colors to progress bar - change color based on usage
            if [ "$pct" -ge 80 ]; then
                progress_bar="\033[31m${bar} ${pct}%\033[0m"  # Red for high usage
            elif [ "$pct" -ge 60 ]; then
                progress_bar="\033[33m${bar} ${pct}%\033[0m"  # Yellow for medium usage
            else
                progress_bar="\033[32m${bar} ${pct}%\033[0m"  # Green for low usage
            fi

            # Get total tokens and context size for display
            total_input=$(echo "$input" | "$jq_cmd" '.context_window.total_input_tokens // 0' 2>/dev/null)
            total_output=$(echo "$input" | "$jq_cmd" '.context_window.total_output_tokens // 0' 2>/dev/null)
            size=$(echo "$input" | "$jq_cmd" '.context_window.context_window_size // 0' 2>/dev/null)

            # Default to 0 if empty
            total_input=${total_input:-0}
            total_output=${total_output:-0}
            size=${size:-0}

            # Ensure we have valid numbers and non-zero size
            if [[ "$total_input" =~ ^[0-9]+$ ]] && [[ "$total_output" =~ ^[0-9]+$ ]] && [[ "$size" =~ ^[0-9]+$ ]] && [[ "$size" -gt 0 ]]; then
                # Calculate total used tokens
                total_used=$((total_input + total_output))

                # Format tokens with K suffix (1 decimal place) - use awk instead of bc
                current_k=$(awk "BEGIN {printf \"%.1f\", $total_used/1000}" 2>/dev/null || echo "0.0")
                size_k=$((size / 1000))

                token_usage="\033[35m${current_k}K\033[0m/\033[35m${size_k}K\033[0m"
            fi
        fi
    fi
else
    # Fallback: skip context window display if jq not available
    :
fi

# Build status line with separators
sep=" \033[37m|\033[0m "
output=""

# Project name with git branch (blue project name, green branch in parentheses)
if [ -n "$git_branch" ]; then
    output+="📁 \033[34m${project_name}\033[0m \033[32m(${git_branch})\033[0m"
else
    output+="📁 \033[34m${project_name}\033[0m"
fi

# Model name (cyan with robot emoji)
output+="${sep}🤖 \033[36m${model_name}\033[0m"

# Progress bar (green)
if [ -n "$progress_bar" ]; then
    output+="${sep}${progress_bar}"
fi

# Token usage (magenta)
if [ -n "$token_usage" ]; then
    output+="${sep}${token_usage}"
fi

# Output the final status line
if [ -n "$output" ]; then
    if $IS_VSCODE; then
        # VS Code terminal optimization: use echo with -e flag for better compatibility
        echo -e "${output}"
    else
        # Terminal.app and other terminals: use printf %b
        printf "%b\n" "${output}"
    fi
else
    # Fallback minimal output if everything fails
    echo "Claude Code"
fi

# Always exit successfully
exit 0
