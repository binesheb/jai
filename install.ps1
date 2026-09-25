#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Repo = "binesheb/jai"
$Root = Join-Path $env:ProgramData "JAI"
$LogDir = Join-Path $Root "logs"
$RepoDir = Join-Path $Root "repo"
New-Item -ItemType Directory -Force -Path $Root,$LogDir | Out-Null
$Log = Join-Path $LogDir ("install-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$StateFile = Join-Path $Root "installation-state.json"
$StartTime = Get-Date
$State = [ordered]@{ GitInstalledByJAI=$false; WslInstalledByJAI=$false; DockerInstalledByJAI=$false; WslDistro=$null; InstalledAt=(Get-Date -Format o); Host=$env:COMPUTERNAME }
if (Test-Path $StateFile) {
  try {
    $saved = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { $State[$p.Name] = $p.Value }
  } catch { }
}
function SaveState { $State | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8 }
$Step = 0

function Log([string]$Message, [string]$Level = "INFO") {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz') [$Level] $Message"
  $line | Tee-Object -FilePath $Log -Append
}
function StepStart([string]$Name) {
  $script:Step++
  Log "STEP $script:Step START: $Name"
  Write-Host ""
  Write-Host "[$script:Step] $Name" -ForegroundColor Cyan
}
function StepEnd([string]$Name) {
  Log "STEP $script:Step COMPLETE: $Name"
  Write-Host "[OK] $Name" -ForegroundColor Green
}
function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path","Machine")
  $user = [Environment]::GetEnvironmentVariable("Path","User")
  $env:Path = "$machine;$user"
  Log "PATH refreshed from Machine + User environment."
}
function Has([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Resolve-Tool([string]$Name, [string[]]$Candidates) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($candidate in $Candidates) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}
function Test-PendingReboot {
  $keys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
  )
  foreach ($key in $keys) { if (Test-Path $key) { return $true } }
  try {
    $session = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Stop
    if ($session.PendingFileRenameOperations) { return $true }
  } catch {}
  return $false
}
function Wait-ForDocker([int]$TimeoutSeconds = 180) {
  Refresh-Path
  if (-not (Has "docker")) {
    StepStart "Installing Docker Desktop"
    Run "winget Docker.DockerDesktop" { winget install --id Docker.DockerDesktop -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity }
    $State.DockerInstalledByJAI=$true;SaveState;Refresh-Path
    StepEnd "Installing Docker Desktop"
  } else { Log "Docker CLI already installed; skipping installation." }

  StepStart "Preparing JAI repository"
  if(-not(Test-Path (Join-Path $RepoDir ".git"))){
    if(Test-Path $RepoDir){Log "Removing incomplete repository directory: $RepoDir" "WARN";Remove-Item -Recurse -Force $RepoDir}
    Run "git clone" {& $GitExe clone "https://github.com/$Repo.git" $RepoDir}
  } else { Run "git fetch" {& $GitExe -C $RepoDir fetch --all --prune};Run "git pull --ff-only" {& $GitExe -C $RepoDir pull --ff-only} }
  $commit=& $GitExe -C $RepoDir rev-parse HEAD;$State.Commit=$commit;SaveState;Log "JAI source revision: $commit"
  StepEnd "Preparing JAI repository"

  StepStart "Starting Docker Engine"
  if(-not(Wait-ForDocker 180)){
    if(Test-PendingReboot){Log "Windows restart appears required." "WARN";Write-Host "RESTART REQUIRED: restart Windows, then run the same JAI command again." -ForegroundColor Yellow;exit 3010}
    throw "Docker Engine did not become ready within 180 seconds. Start Docker Desktop and rerun JAI."
  }
  StepEnd "Starting Docker Engine"

  StepStart "Configuring JAI infrastructure"
  Ensure-ComposeEnv
  $compose=Join-Path $RepoDir "docker-compose.yml"
  if(-not(Test-Path $compose)){throw "docker-compose.yml is missing."}
  Run "docker compose config" {Push-Location $RepoDir;try{docker compose config}finally{Pop-Location}}
  Run "docker compose pull" {Push-Location $RepoDir;try{docker compose pull}finally{Pop-Location}}
  Run "docker compose up -d" {Push-Location $RepoDir;try{docker compose up -d}finally{Pop-Location}}
  Run "docker compose ps" {Push-Location $RepoDir;try{docker compose ps}finally{Pop-Location}}
  StepEnd "Configuring JAI infrastructure"

  $elapsed = (Get-Date) - $StartTime
  SaveState
  Log "JAI bootstrap completed successfully in $([math]::Round($elapsed.TotalSeconds,1)) seconds."
  Write-Host ""
  Write-Host "JAI bootstrap completed successfully." -ForegroundColor Green
  Write-Host "Detailed log: $Log" -ForegroundColor Yellow
  Write-Host "Repository: $RepoDir"
  Write-Host "Infrastructure: Docker Compose services started."
} catch {
  Log "JAI bootstrap FAILED: $($_.Exception.Message)" "ERROR"
  Log "Stack: $($_.ScriptStackTrace)" "ERROR"
  Write-Host ""
  Write-Host "JAI bootstrap FAILED." -ForegroundColor Red
  Write-Host "Detailed log: $Log" -ForegroundColor Yellow
  Write-Host "Send this log if you want me to diagnose the failure."
  exit 1
}
