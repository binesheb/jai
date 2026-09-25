#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Repo = "binesheb/jai"
$Root = Join-Path $env:ProgramData "JAI"
$LogDir = Join-Path $Root "logs"
$RepoDir = Join-Path $Root "repo"
New-Item -ItemType Directory -Force -Path $Root,$LogDir | Out-Null
$Log = Join-Path $LogDir ("install-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

function Log($Message) {
  $line = "$(Get-Date -Format o) $Message"
  $line | Tee-Object -FilePath $Log -Append
}

function Has($Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

Log "JAI bootstrap started."
Log "Host: $env:COMPUTERNAME"
Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
Log "RAM_GB: $([math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1))"

if (-not (Has "git")) {
  Log "Git not found. Installing Git via winget."
  if (-not (Has "winget")) { throw "winget is required. Install App Installer from Microsoft Store." }
  winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
}
if (-not (Has "wsl")) {
  Log "WSL command not found. Installing WSL."
  wsl --install --no-distribution
  Log "WSL installation requested. A restart may be required."
}
if (-not (Has "docker")) {
  Log "Docker CLI not found. Attempting Docker Desktop installation."
  if (-not (Has "winget")) { throw "winget is required to install Docker Desktop." }
  winget install --id Docker.DockerDesktop -e --source winget --accept-source-agreements --accept-package-agreements
}

if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
  Log "Cloning JAI repository."
  if (Test-Path $RepoDir) { Remove-Item -Recurse -Force $RepoDir }
  git clone "https://github.com/$Repo.git" $RepoDir
} else {
  Log "Updating JAI repository."
  git -C $RepoDir fetch --all --prune
  git -C $RepoDir pull --ff-only
}

Log "Checking Docker."
if (Has "docker") { docker version | Out-File -FilePath $Log -Append }
Log "Running JAI bootstrap health check when Docker Compose is available."
if ((Has "docker") -and (Test-Path (Join-Path $RepoDir "docker-compose.yml"))) {
  Push-Location $RepoDir
  try { docker compose config | Out-File -FilePath $Log -Append } finally { Pop-Location }
}

Log "JAI bootstrap completed. Repository: $RepoDir"
Write-Host ""
Write-Host "JAI bootstrap completed."
Write-Host "Logs: $Log"
Write-Host "Repository: $RepoDir"
