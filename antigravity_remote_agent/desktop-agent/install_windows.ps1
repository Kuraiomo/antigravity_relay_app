# Antigravity Desktop Agent — Windows Setup Script
# Run this in PowerShell as the current user (no admin required).

param(
    [switch]$AutoStart,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$AgentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir = Join-Path $AgentDir ".venv"
$StartupKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$StartupName = "AntigravityAgent"

function Write-Step($msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

# ── Uninstall ────────────────────────────────────────────────────────────────

if ($Uninstall) {
    Write-Step "Removing Windows startup registration..."
    Remove-ItemProperty -Path $StartupKey -Name $StartupName -ErrorAction SilentlyContinue
    Write-Host "Startup registration removed."

    Write-Step "Removing virtual environment..."
    if (Test-Path $VenvDir) {
        Remove-Item -Recurse -Force $VenvDir
        Write-Host "Virtual environment removed."
    }

    Write-Host "`nUninstall complete. You may delete the desktop-agent directory manually." -ForegroundColor Green
    exit 0
}

# ── Install ──────────────────────────────────────────────────────────────────

Write-Step "Checking Python version..."
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Write-Host "ERROR: Python not found. Install Python 3.10+ and add it to PATH." -ForegroundColor Red
    exit 1
}
$version = & python --version 2>&1
Write-Host "Found: $version"

Write-Step "Creating virtual environment..."
if (-not (Test-Path $VenvDir)) {
    & python -m venv $VenvDir
}
Write-Host "Virtual environment: $VenvDir"

Write-Step "Activating virtual environment..."
$activateScript = Join-Path $VenvDir "Scripts\Activate.ps1"
. $activateScript

Write-Step "Installing dependencies..."
& pip install -e ".$AgentDir[dev]" --quiet
if ($LASTEXITCODE -ne 0) {
    # Fallback: install from requirements.txt
    & pip install -r (Join-Path $AgentDir "requirements.txt") --quiet
}
Write-Host "Dependencies installed."

Write-Step "Setting up configuration..."
$envFile = Join-Path $AgentDir ".env"
$envExample = Join-Path $AgentDir ".env.example"
if (-not (Test-Path $envFile)) {
    Copy-Item $envExample $envFile
    Write-Host "Created .env from .env.example — please edit it with your settings."
} else {
    Write-Host ".env already exists."
}

# ── Optional: Windows startup ────────────────────────────────────────────────

if ($AutoStart) {
    Write-Step "Registering Windows startup..."
    $pythonExe = Join-Path $VenvDir "Scripts\python.exe"
    $mainModule = Join-Path $AgentDir "app\main.py"
    $cmd = "`"$pythonExe`" `"$mainModule`""
    Set-ItemProperty -Path $StartupKey -Name $StartupName -Value $cmd
    Write-Host "Registered: $cmd"
    Write-Host "The agent will start automatically on login."
} else {
    Write-Host "`nTip: Run with -AutoStart to register for Windows startup." -ForegroundColor Yellow
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  To start the agent:" -ForegroundColor Green
Write-Host "    cd $AgentDir" -ForegroundColor Green
Write-Host "    .venv\Scripts\Activate.ps1" -ForegroundColor Green
Write-Host "    python -m app.main" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
