#!/usr/bin/env bash
input=$(cat)

# Git branch
git_branch=$(git -C "$(echo "$input" | jq -r '.workspace.current_dir')" --no-optional-locks branch --show-current 2>/dev/null)
if [ -n "$git_branch" ]; then
  git_part="$git_branch"
else
  git_part=""
fi

# Model display name
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')

# Context window data
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')

if [ -n "$used_pct" ] && [ -n "$input_tokens" ] && [ -n "$context_size" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  tokens_part="${used_int}% | ${input_tokens}/${context_size} tokens"
elif [ -n "$context_size" ]; then
  tokens_part="0% | 0/${context_size} tokens"
else
  tokens_part="tokens: -"
fi

# Assemble parts
parts=()
[ -n "$git_part" ] && parts+=("$git_part")
parts+=("$model")
parts+=("$tokens_part")

printf "%s" "$(IFS=' | '; echo "${parts[*]}")"
