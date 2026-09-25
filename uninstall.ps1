#requires -Version 5.1
$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

$Root = Join-Path $env:ProgramData "JAI"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("uninstall-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$RepoDir = Join-Path $Root "repo"
$StateFile = Join-Path $Root "installation-state.json"

function Log([string]$Message,[string]$Level="INFO") {
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz') [$Level] $Message" | Tee-Object -FilePath $Log -Append
}
function RemovePath([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    Log "Removing: $Path"
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; Log "Removed: $Path" }
    catch { Log "Could not remove $Path : $($_.Exception.Message)" "WARN" }
  }
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host " JAI - COMPLETE UNINSTALLER" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "This removes JAI and JAI-managed data from this PC."
Write-Host "It does NOT remove Git, WSL or Docker if they existed before JAI." -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Type REMOVE-JAI to continue"
if ($confirm -ne "REMOVE-JAI") {
  Write-Host "Cancelled."
  exit 0
}

Log "JAI uninstall started."
$State = $null
if (Test-Path $StateFile) {
  try { $State = Get-Content $StateFile -Raw | ConvertFrom-Json; Log "Installation state loaded." }
  catch { Log "Could not read installation state; shared prerequisites will be preserved." "WARN" }
}

# Stop and remove only JAI's container resources.
if (Get-Command docker -ErrorAction SilentlyContinue) {
  $compose = Join-Path $RepoDir "docker-compose.yml"
  if (Test-Path $compose) {
    Log "Stopping JAI Docker services and removing JAI project volumes."
    Push-Location $RepoDir
    try {
      docker compose down --volumes --remove-orphans --rmi local 2>&1 | ForEach-Object { Log "docker :: $($_.ToString())" }
    } catch { Log "Docker cleanup failed: $($_.Exception.Message)" "WARN" }
    finally { Pop-Location }
  }
}

# Remove JAI-specific scheduled tasks/services if later versions create them.
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
  $_.TaskName -like "JAI*" -or $_.TaskPath -like "\JAI\*"
} | ForEach-Object {
  Log "Removing scheduled task: $($_.TaskName)"
  Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# Remove the JAI installation tree, including logs, config, database data and models stored there.
RemovePath $Root

# Remove only prerequisites that this JAI installation explicitly installed.
if ($State) {
  if ($State.DockerInstalledByJAI -eq $true -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Log "JAI installed Docker Desktop; attempting removal."
    winget uninstall --id Docker.DockerDesktop -e --source winget --accept-source-agreements --silent 2>&1 | ForEach-Object { Log "winget :: $($_.ToString())" }
  }
  if ($State.GitInstalledByJAI -eq $true -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Log "JAI installed Git; attempting removal."
    winget uninstall --id Git.Git -e --source winget --accept-source-agreements --silent 2>&1 | ForEach-Object { Log "winget :: $($_.ToString())" }
  }
  # WSL is intentionally not automatically removed because it is a Windows subsystem
  # that may be used by other software. A future JAI-created distro can be removed safely
  # when its name is recorded in installation-state.json.
}

# Best-effort cleanup of JAI-specific environment variables.
[Environment]::SetEnvironmentVariable("JAI_HOME",$null,"Machine")
[Environment]::SetEnvironmentVariable("JAI_HOME",$null,"User")

Write-Host ""
Write-Host "JAI uninstall completed." -ForegroundColor Green
Write-Host "JAI-specific files, containers, volumes and configuration have been removed."
Log "JAI uninstall completed."
Write-Host "Cleanup log: $Log" -ForegroundColor DarkGray
# The log is itself removed to honor the clean-uninstall requirement.
Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue
