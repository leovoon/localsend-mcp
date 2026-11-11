#!/usr/bin/env bash
# Automated Git synchronization, secret scanner, and build runner for localsend-mcp (macOS/Linux).

set -u

MESSAGE=""
PULL_ONLY=0
PUSH_ONLY=0
NO_PUSH=0
NO_BUILD=0
WHAT_IF=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message) MESSAGE="$2"; shift 2 ;;
    --pull-only) PULL_ONLY=1; shift ;;
    --push-only) PUSH_ONLY=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --what-if|-n) WHAT_IF=1; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

ts() { date +"%H:%M:%S"; }
status() { echo "[$(ts)] $*" ; }
notice() { echo "[$(ts)] $*" >&2; }
success() { echo "[$(ts)] $*" ; }
fail() { echo "[$(ts)] $*" >&2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -d "$REPO_ROOT/.git" ]]; then
  fail "Error: Not a git repository ($REPO_ROOT)."
  exit 1
fi
cd "$REPO_ROOT"

if [[ $PULL_ONLY -eq 1 ]]; then
  status "Pulling latest updates with rebase..."
  if [[ $WHAT_IF -eq 1 ]]; then
    notice "[WhatIf] Would execute: git pull --rebase --autostash origin main"
  else
    git pull --rebase --autostash origin main
    success "Pull complete."
  fi
  exit 0
fi

if [[ $PUSH_ONLY -eq 1 ]]; then
  status "Pushing existing commits to origin main..."
  if [[ $WHAT_IF -eq 1 ]]; then
    notice "[WhatIf] Would execute: git push origin main"
  else
    git push origin main
    success "Push complete."
  fi
  exit 0
fi

# Automatic build check
needs_build=0
if git status --porcelain | grep -q 'src/.*\.ts'; then needs_build=1; fi
if [[ $needs_build -eq 1 && $NO_BUILD -eq 0 ]]; then
  status "TypeScript changes detected. Compiling localsend-mcp..."
  if [[ $WHAT_IF -eq 1 ]]; then
    notice "[WhatIf] Would execute: npm run build"
  else
    npm run build
    if [[ $? -ne 0 ]]; then fail "Build failed. Aborting sync."; exit $?; fi
    success "TypeScript compilation succeeded."
  fi
fi

status_output="$(git status --porcelain)"
has_changes=0
[[ -n "$status_output" ]] && has_changes=1

if [[ $has_changes -eq 0 ]]; then
  unpushed="$(git log '@{u}..HEAD' --oneline 2>/dev/null)"
  if [[ -n "$unpushed" ]]; then
    notice "Working directory clean, but unpushed commits exist:"
    echo "$unpushed" | sed 's/^/  - /'
    if [[ $NO_PUSH -eq 0 ]]; then
      status "Pushing unpushed commits to origin main..."
      if [[ $WHAT_IF -eq 1 ]]; then
        notice "[WhatIf] Would execute: git push origin main"
      else
        git push origin main
        success "Push complete."
      fi
    fi
  else
    success "Working directory clean and up to date with origin/main. Nothing to commit."
  fi
  exit 0
fi

status "Detected modified / untracked files:"
git status -s | sed 's/^/  /'

if [[ $WHAT_IF -eq 1 ]]; then
  if [[ -n "$MESSAGE" ]]; then preview="$MESSAGE"; else preview="(auto)"; fi
  notice "[WhatIf] Commit message: $preview"
  notice "[WhatIf] Dry-run complete. No changes made."
  exit 0
fi

status "Fetching remote updates..."
git fetch origin main >/dev/null 2>&1

status "Staging changes..."
git add -A

# Secret scanner
secret_hits=0
added_lines="$(git diff --cached -U0 | grep '^+[^+]' | sed 's/^+//')"
if [[ -n "$added_lines" ]]; then
  patterns=(
    'AKIA[0-9A-Z]{16}'
    'sk-[a-zA-Z0-9]{20,}'
    'sk-ant-[a-zA-Z0-9\-]{20,}'
    'ghp_[a-zA-Z0-9]{36}'
    'github_pat_[a-zA-Z0-9_]{20,}'
    'AIza[0-9A-Za-z\-_]{35}'
    'xox[baprs]-[0-9a-zA-Z\-]{10,}'
    '-----BEGIN (RSA|EC|OPENSSH|PGP|DSA)? ?PRIVATE KEY-----'
  )
  while IFS= read -r line; do
    for p in "${patterns[@]}"; do
      if echo "$line" | grep -Eq "$p"; then
        fail "CRITICAL: Secret scanner blocked commit! Pattern: $p"
        secret_hits=1
        break
      fi
    done
    [[ $secret_hits -eq 1 ]] && break
  done <<< "$added_lines"
fi

if [[ $secret_hits -eq 1 ]]; then
  notice "Unstaging changes to protect repository..."
  git reset >/dev/null
  exit 1
fi

# Commit message
if [[ -n "$MESSAGE" ]]; then
  commit_msg="$MESSAGE"
else
  commit_msg="chore(localsend): update ecosystem components"
fi

status "Committing changes with message: '$commit_msg'..."
git commit -m "$commit_msg"
if [[ $? -ne 0 ]]; then fail "Commit failed."; exit $?; fi
success "Commit created."

if [[ $NO_PUSH -eq 1 ]]; then
  notice "NoPush specified. Changes committed locally."
else
  status "Pushing with rebase to origin main..."
  git pull --rebase --autostash origin main
  git push origin main
  if [[ $? -ne 0 ]]; then fail "Push failed."; exit $?; fi
  success "Successfully synchronized and pushed to https://github.com/Aaradhya-Dev-Tamrakar/localsend-mcp"
fi
