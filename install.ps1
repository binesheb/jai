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
function Run([string]$Name, [scriptblock]$Command) {
  Log "COMMAND START: $Name"
  try {
    & $Command 2>&1 | ForEach-Object {
      $text = $_.ToString()
      Log "$Name :: $text"
      Write-Host $text
    }
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
    Log "COMMAND COMPLETE: $Name"
  } catch {
    Log "COMMAND FAILED: $Name :: $($_.Exception.Message)" "ERROR"
    throw
  }
}

try {
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host " JAI - WINDOWS BOOTSTRAP" -ForegroundColor Cyan
  Write-Host " Detailed installation logging enabled" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "Live log: $Log" -ForegroundColor Yellow
  Log "JAI bootstrap started."
  Refresh-Path
  Log "PowerShell: $($PSVersionTable.PSVersion)"
  Log "User: $env:USERNAME"
  Log "Host: $env:COMPUTERNAME"
  Log "Working directory: $(Get-Location)"
  $os = Get-CimInstance Win32_OperatingSystem
  $cs = Get-CimInstance Win32_ComputerSystem
  Log "OS: $($os.Caption) build $($os.BuildNumber)"
  Log "Architecture: $($os.OSArchitecture)"
  Log "RAM_GB: $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1))"
  Log "System drive free GB: $([math]::Round((Get-PSDrive C).Free / 1GB, 1))"
  Log "Repository: https://github.com/$Repo"

  StepStart "Detecting prerequisites"
  foreach ($tool in @("winget","git","wsl","docker")) {
    if (Has $tool) {
      try { $v = & $tool --version 2>&1 | Select-Object -First 1; Log "$tool detected: $v"; Write-Host "[FOUND] $tool : $v" }
      catch { Log "$tool detected but version check failed: $($_.Exception.Message)" "WARN" }
    } else { Log "$tool not found."; Write-Host "[MISSING] $tool" -ForegroundColor Yellow }
  }
  StepEnd "Prerequisite detection"

  if (-not (Has "winget")) {
    throw "winget is required. Install Microsoft App Installer, then rerun JAI."
  }

  Refresh-Path
  $GitExe = Resolve-Tool "git" @("$env:ProgramFiles\Git\cmd\git.exe","$env:ProgramFiles\Git\bin\git.exe","$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
  if ($GitExe) {
    Log "Git already installed and resolved to: $GitExe; skipping winget."
  } else {
    StepStart "Installing Git"
    # winget can return a non-zero code when the package is already installed.
    Run "winget Git.Git" { winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity }
    Refresh-Path
    $GitExe = Resolve-Tool "git" @("$env:ProgramFiles\Git\cmd\git.exe","$env:ProgramFiles\Git\bin\git.exe","$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
    if (-not $GitExe) { throw "Git was not found after installation. Restart PowerShell and rerun the installer." }
    $State.GitInstalledByJAI=$true; SaveState
    Log "Git executable resolved to: $GitExe"
    StepEnd "Installing Git"
  }
  Log "Using Git executable: $GitExe"

  if (-not (Has "wsl")) {
    StepStart "Installing WSL"
    Run "wsl --install" { wsl --install --no-distribution }
    $State.WslInstalledByJAI=$true; SaveState
    Log "WSL installation requested. Windows restart may be required." "WARN"
    StepEnd "Installing WSL"
  } else { Log "WSL already installed; checking status."; Run "wsl --status" { wsl --status } }

  if (-not (Has "docker")) {
    StepStart "Installing Docker Desktop"
    Run "winget Docker.DockerDesktop" { winget install --id Docker.DockerDesktop -e --source winget --accept-source-agreements --accept-package-agreements }
    $State.DockerInstalledByJAI=$true; SaveState
    Refresh-Path
    Log "Docker Desktop installation completed. The Docker CLI may require Docker Desktop to be started before it becomes available." "WARN"
    StepEnd "Installing Docker Desktop"
  } else { Log "Docker CLI already installed; skipping installation." }

  StepStart "Preparing JAI repository"
  if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    if (Test-Path $RepoDir) {
      Log "Removing incomplete repository directory: $RepoDir" "WARN"
      Remove-Item -Recurse -Force $RepoDir
    }
    Run "git clone" { & $GitExe clone "https://github.com/$Repo.git" $RepoDir }
  } else {
    Run "git fetch" { & $GitExe -C $RepoDir fetch --all --prune }
    Run "git pull --ff-only" { & $GitExe -C $RepoDir pull --ff-only }
  }
  $commit = & $GitExe -C $RepoDir rev-parse HEAD
  $State.Commit=$commit; SaveState
  Log "JAI source revision: $commit"
  StepEnd "Preparing JAI repository"

  StepStart "Validating Docker"
  Refresh-Path
  if (-not (Has "docker")) {
    $dockerCandidates = @("$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe","$env:ProgramFiles\Docker\Docker\resources\bin\docker-compose.exe")
    $docker = Resolve-Tool "docker" $dockerCandidates
    if ($docker) { $env:Path = "$(Split-Path $docker);$env:Path"; Log "Docker executable resolved to: $docker" }
  }
  if (-not (Has "docker")) { throw "Docker CLI is unavailable after installation. Start Docker Desktop, then rerun JAI." }
  Run "docker version" { docker version }
  $compose = Join-Path $RepoDir "docker-compose.yml"
  if (Test-Path $compose) {
    Run "docker compose config" { Push-Location $RepoDir; try { docker compose config } finally { Pop-Location } }
  } else { Log "docker-compose.yml not present yet; infrastructure startup will be added in a later bootstrap phase." "WARN" }
  StepEnd "Validating Docker"

  $elapsed = (Get-Date) - $StartTime
  SaveState
  Log "JAI bootstrap completed successfully in $([math]::Round($elapsed.TotalSeconds,1)) seconds."
  Write-Host ""
  Write-Host "JAI bootstrap completed successfully." -ForegroundColor Green
  Write-Host "Detailed log: $Log" -ForegroundColor Yellow
  Write-Host "Repository: $RepoDir"
} catch {
  Log "JAI bootstrap FAILED: $($_.Exception.Message)" "ERROR"
  Log "Stack: $($_.ScriptStackTrace)" "ERROR"
  Write-Host ""
  Write-Host "JAI bootstrap FAILED." -ForegroundColor Red
  Write-Host "Detailed log: $Log" -ForegroundColor Yellow
  Write-Host "Send this log if you want me to diagnose the failure."
  exit 1
}
