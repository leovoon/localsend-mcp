<#
.SYNOPSIS
    Automated Git synchronization, secret scanner, and build runner for localsend-mcp.

.DESCRIPTION
    sync.ps1 - The central synchronization script for the LocalSend MCP server repository:
    https://github.com/Aaradhya-Dev-Tamrakar/localsend-mcp

    Capabilities:
    1. Pre-Commit Secret Scanner Guard: Prevents committing TLS private keys, tokens, or credentials.
    2. Automatic TypeScript Build: Automatically runs `npm run build` when source files change.
    3. Intelligent Conventional Commits: Auto-formats scoped commit messages (feat(localsend), docs(localsend), etc.).
    4. Safe Rebase & Push: Pulls with --rebase --autostash before pushing to origin/main.
    5. Dry-Run Mode (-WhatIf): Previews changes and secret scan without touching git state.

.PARAMETER Message
    Custom commit message (alias: -m). If omitted, an intelligent conventional commit is generated.

.PARAMETER PullOnly
    Pulls remote updates with --rebase --autostash without staging or pushing.

.PARAMETER PushOnly
    Pushes existing local commits without creating new commits.

.PARAMETER NoPush
    Stages and commits changes locally without pushing to origin.

.PARAMETER NoBuild
    Skips the automatic TypeScript compilation step.

.PARAMETER WhatIf
    Dry-run mode: inspects changes and runs secret scanner without altering git state.

.EXAMPLE
    .\sync.ps1                                   # Routine build, sync, and push
    .\sync.ps1 -m "feat(localsend): add clipboard sync" # Custom commit message
    .\sync.ps1 -PullOnly                         # Pull latest changes safely
    .\sync.ps1 -WhatIf                           # Dry-run preview
#>

[CmdletBinding()]
param (
    [Alias("m")]
    [string]$Message,

    [switch]$PullOnly,
    [switch]$PushOnly,
    [switch]$NoPush,
    [switch]$NoBuild,
    [switch]$WhatIf
)

$ErrorActionPreference = "Continue"

function Write-Status {
    param(
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Cyan
    )
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

function Write-Notice {
    param([string]$Message)
    Write-Status -Message $Message -Color ([System.ConsoleColor]::Yellow)
}

function Write-Success {
    param([string]$Message)
    Write-Status -Message $Message -Color ([System.ConsoleColor]::Green)
}

function Write-Failure {
    param([string]$Message)
    Write-Status -Message $Message -Color ([System.ConsoleColor]::Red)
}

function Find-StagedSecrets {
    $stagedDiff = git diff --cached -U0 2>$null
    if (-not $stagedDiff) { return @() }

    $addedLines = $stagedDiff | Where-Object { $_ -match '^\+[^+]' } | ForEach-Object { $_.Substring(1) }
    if (-not $addedLines) { return @() }

    $secretPatterns = @(
        'AKIA[0-9A-Z]{16}',
        'sk-[a-zA-Z0-9]{20,}',
        'sk-ant-[a-zA-Z0-9\-]{20,}',
        'ghp_[a-zA-Z0-9]{36}',
        'github_pat_[a-zA-Z0-9_]{20,}',
        'AIza[0-9A-Za-z\-_]{35}',
        'xox[baprs]-[0-9a-zA-Z\-]{10,}',
        '-----BEGIN (RSA|EC|OPENSSH|PGP|DSA)? ?PRIVATE KEY-----',
        '(?i)(api[_-]?key|client_secret|access_token|refresh_token|password)\s*[:=]\s*[''"][^''"\s]{8,}[''"]'
    )

    $hits = @()
    foreach ($line in $addedLines) {
        foreach ($pattern in $secretPatterns) {
            if ($line -match $pattern) {
                $snippet = $line.Trim()
                $hits += [PSCustomObject]@{
                    Pattern = $pattern
                    Snippet = $snippet.Substring(0, [Math]::Min(60, $snippet.Length))
                }
                break
            }
        }
    }

    return @($hits)
}

function Get-AutoCommitMessage {
    $statusLines = git status --porcelain
    if (-not $statusLines) { return $null }

    $modifiedFiles = @()
    $addedFiles = @()
    $deletedFiles = @()

    foreach ($line in $statusLines) {
        if ($line.Length -lt 3) { continue }
        $status = $line.Substring(0, 2).Trim()
        $file = $line.Substring(3).Trim()
        $fileName = Split-Path $file -Leaf

        if ($status -match 'A|\?\?') { $addedFiles += $fileName }
        elseif ($status -match 'D') { $deletedFiles += $fileName }
        else { $modifiedFiles += $fileName }
    }

    $allChanged = @($addedFiles + $modifiedFiles + $deletedFiles)
    if (@($allChanged).Count -eq 0) { return $null }

    $prefix = "chore(localsend)"
    if (@($addedFiles).Count -gt 0) { $prefix = "feat(localsend)" }
    elseif ($modifiedFiles | Where-Object { $_ -match '\.md$' }) { $prefix = "docs(localsend)" }
    elseif ($modifiedFiles | Where-Object { $_ -match '\.(ts|js|json)$' }) { $prefix = "refactor(localsend)" }

    $summary = ($allChanged | Select-Object -First 3) -join ", "
    if (@($allChanged).Count -gt 3) {
        $summary += " (+$(@($allChanged).Count - 3) more)"
    }

    return "$($prefix): update $($summary)"
}

# --- Main Execution ---
Write-Status "================================================================"
Write-Status "LOCALSEND MCP - Git and Ecosystem Synchronizer"
Write-Status "================================================================"

$repoRoot = $PSScriptRoot
if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
    Write-Failure "Error: Not a git repository ($repoRoot)."
    exit 1
}

# 1. Pull Only Mode
if ($PullOnly) {
    Write-Status "Pulling latest updates with rebase..."
    if ($WhatIf) {
        Write-Notice "[WhatIf] Would execute: git pull --rebase --autostash origin main"
    } else {
        git pull --rebase --autostash origin main
        Write-Success "Pull complete."
    }
    exit 0
}

# 2. Push Only Mode
if ($PushOnly) {
    Write-Status "Pushing existing commits to origin main..."
    if ($WhatIf) {
        Write-Notice "[WhatIf] Would execute: git push origin main"
    } else {
        git push origin main
        Write-Success "Push complete."
    }
    exit 0
}

# 3. Automatic Build Check
$needsBuild = $false
$statusRaw = git status --porcelain
if ($statusRaw -match 'src/.*\.ts') {
    $needsBuild = $true
}

if ($needsBuild -and (-not $NoBuild)) {
    Write-Status "TypeScript changes detected. Compiling localsend-mcp..."
    if ($WhatIf) {
        Write-Notice "[WhatIf] Would execute: npm run build"
    } else {
        npm run build
        if ($LASTEXITCODE -ne 0) {
            Write-Failure "Build failed. Aborting sync."
            exit $LASTEXITCODE
        }
        Write-Success "TypeScript compilation succeeded."
    }
}

# 4. Check git status
$statusOutput = git status --porcelain
$hasChanges = [bool]($statusOutput)

if (-not $hasChanges) {
    $unpushed = git log '@{u}..HEAD' --oneline 2>$null
    if ($unpushed) {
        Write-Notice "Working directory clean, but unpushed commits exist:"
        $unpushed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        if (-not $NoPush) {
            Write-Status "Pushing unpushed commits to origin main..."
            if ($WhatIf) {
                Write-Notice "[WhatIf] Would execute: git push origin main"
            } else {
                git push origin main
                Write-Success "Push complete."
            }
        }
    } else {
        Write-Success "Working directory clean and up to date with origin/main. Nothing to commit."
    }
    exit 0
}

# 5. Review Changes
Write-Status "Detected modified / untracked files:"
git status -s | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }

if ($WhatIf) {
    $previewMsg = if ($Message) { $Message } else { Get-AutoCommitMessage }
    Write-Notice "[WhatIf] Commit message: $previewMsg"
    Write-Notice "[WhatIf] Dry-run complete. No changes made."
    exit 0
}

# 6. Fetch remote updates
Write-Status "Fetching remote updates..."
git fetch origin main *> $null

# 7. Stage files
Write-Status "Staging changes..."
git add -A

# 8. Secret Scanner Guard
$secretHits = Find-StagedSecrets
if (@($secretHits).Count -gt 0) {
    Write-Failure "CRITICAL: Secret scanner blocked commit! Sensitive credential patterns detected in staged files:"
    foreach ($hit in $secretHits) {
        Write-Host "  Pattern : $($hit.Pattern)" -ForegroundColor Red
        Write-Host "  Snippet : $($hit.Snippet)..." -ForegroundColor Yellow
    }
    Write-Notice "Unstaging changes to protect repository..."
    git reset
    exit 1
}

# 9. Format Commit Message
$commitMsg = if ($Message) { $Message } else { Get-AutoCommitMessage }
if (-not $commitMsg) {
    $commitMsg = "chore(localsend): update ecosystem components"
}

Write-Status "Committing changes with message: '$commitMsg'..."
git commit -m "$commitMsg"
if ($LASTEXITCODE -ne 0) {
    Write-Failure "Commit failed."
    exit $LASTEXITCODE
}
Write-Success "Commit created."

# 10. Push with rebase
if ($NoPush) {
    Write-Notice "NoPush specified. Changes committed locally."
} else {
    Write-Status "Pushing with rebase to origin main..."
    git pull --rebase --autostash origin main
    git push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Push failed."
        exit $LASTEXITCODE
    }
    Write-Success "Successfully synchronized and pushed to https://github.com/Aaradhya-Dev-Tamrakar/localsend-mcp"
}
