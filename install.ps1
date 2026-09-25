#requires -Version 5.1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Repo = "binesheb/jai"
$Root = Join-Path $env:ProgramData "JAI"
$LogDir = Join-Path $Root "logs"
$RepoDir = Join-Path $Root "repo"
New-Item -ItemType Directory -Force -Path $Root, $LogDir | Out-Null

$Log = Join-Path $LogDir ("install-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$StateFile = Join-Path $Root "installation-state.json"
$StartTime = Get-Date
$State = [ordered]@{
  GitInstalledByJAI = $false
  WslInstalledByJAI = $false
  DockerInstalledByJAI = $false
  WslDistro = $null
  InstalledAt = (Get-Date -Format o)
  Host = $env:COMPUTERNAME
}

if (Test-Path $StateFile) {
  try {
    $saved = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) {
      $State[$p.Name] = $p.Value
    }
  } catch {
    # State is advisory; a corrupt state file must not prevent a fresh bootstrap.
  }
}

function Save-State {
  $State | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

function Log([string]$Message, [string]$Level = "INFO") {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz') [$Level] $Message"
  $line | Tee-Object -FilePath $Log -Append
}

function Step-Start([string]$Name) {
  $script:Step++
  Log "STEP $script:Step START: $Name"
  Write-Host ""
  Write-Host "[$script:Step] $Name" -ForegroundColor Cyan
}

function Step-End([string]$Name) {
  Log "STEP $script:Step COMPLETE: $Name"
  Write-Host "[OK] $Name" -ForegroundColor Green
}

function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machine;$user"
  Log "PATH refreshed from Machine + User environment."
}

function Has([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-Tool([string]$Name, [string[]]$Candidates) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }
  foreach ($candidate in $Candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  return $null
}

function Test-Pending-Reboot {
  $keys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
  )

  foreach ($key in $keys) {
    if (Test-Path $key) {
      return $true
    }
  }

  try {
    $session = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Stop
    if ($session.PendingFileRenameOperations) {
      return $true
    }
  } catch {}

  return $false
}

function Run-Command([string]$Name, [scriptblock]$Command) {
  Log "COMMAND START: $Name"
  try {
    & $Command 2>&1 | ForEach-Object {
      $text = $_.ToString()
      Log "$Name :: $text"
      Write-Host $text
    }

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
      throw "Exit code $LASTEXITCODE"
    }

    Log "COMMAND COMPLETE: $Name"
  } catch {
    Log "COMMAND FAILED: $Name :: $($_.Exception.Message)" "ERROR"
    throw
  }
}

function Wait-ForDocker([int]$TimeoutSeconds = 180) {
  Refresh-Path

  $dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
  if (-not (Has "docker") -and (Test-Path -LiteralPath $dockerExe)) {
    $env:Path = "$(Split-Path $dockerExe);$env:Path"
    Log "Docker CLI resolved to: $dockerExe"
  }

  $desktopExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  if ((Test-Path -LiteralPath $desktopExe) -and -not (Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue)) {
    Log "Docker Desktop is installed but not running. Starting it."
    Start-Process -FilePath $desktopExe
  }

  if (-not (Has "docker")) {
    Log "Docker CLI is not available yet." "WARN"
    return $false
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      & docker version --format "{{.Server.Version}}" 2>&1 | ForEach-Object {
        Log "docker server :: $($_.ToString())"
      }
      if ($LASTEXITCODE -eq 0) {
        Log "Docker Engine is ready."
        return $true
      }
    } catch {}

    Start-Sleep -Seconds 5
  }

  return $false
}

function Ensure-Compose-Env {
  $envFile = Join-Path $RepoDir ".env"

  if (Test-Path -LiteralPath $envFile) {
    Log "Existing local .env found; preserving it."
    return
  }

  $bytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }

  $password = [Convert]::ToBase64String($bytes).Replace("+", "-").Replace("/", "_").Replace("=", "")

  @(
    "JAI_POSTGRES_DB=jai"
    "JAI_POSTGRES_USER=jai"
    "JAI_POSTGRES_PASSWORD=$password"
    "JAI_POSTGRES_PORT=5432"
    "JAI_REDIS_PORT=6379"
  ) | Set-Content -Path $envFile -Encoding UTF8

  Log "Created local JAI .env with a generated PostgreSQL password. The file is not committed."
}

$Step = 0

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

  Step-Start "Detecting prerequisites"
  foreach ($tool in @("winget", "git", "wsl", "docker")) {
    if (Has $tool) {
      try {
        $v = & $tool --version 2>&1 | Select-Object -First 1
        Log "$tool detected: $v"
        Write-Host "[FOUND] $tool : $v"
      } catch {
        Log "$tool detected but version check failed: $($_.Exception.Message)" "WARN"
      }
    } else {
      Log "$tool not found."
      Write-Host "[MISSING] $tool" -ForegroundColor Yellow
    }
  }
  Step-End "Prerequisite detection"

  if (-not (Has "winget")) {
    throw "winget is required. Install Microsoft App Installer, then rerun JAI."
  }

  # Git
  Refresh-Path
  $GitExe = Resolve-Tool "git" @(
    "$env:ProgramFiles\Git\cmd\git.exe",
    "$env:ProgramFiles\Git\bin\git.exe",
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
  )

  if ($GitExe) {
    Log "Git already installed and resolved to: $GitExe; skipping WinGet."
  } else {
    Step-Start "Installing Git"
    Run-Command "winget Git.Git" {
      winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    }
    Refresh-Path
    $GitExe = Resolve-Tool "git" @(
      "$env:ProgramFiles\Git\cmd\git.exe",
      "$env:ProgramFiles\Git\bin\git.exe",
      "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )
    if (-not $GitExe) {
      throw "Git was not found after installation. Restart PowerShell and rerun JAI."
    }
    $State.GitInstalledByJAI = $true
    Save-State
    Log "Git executable resolved to: $GitExe"
    Step-End "Installing Git"
  }

  Log "Using Git executable: $GitExe"

  # WSL
  Refresh-Path
  $wslExe = Resolve-Tool "wsl" @("$env:SystemRoot\System32\wsl.exe")
  $wslReady = $false

  if ($wslExe) {
    Log "WSL executable found: $wslExe"
    try {
      $wslStatus = & $wslExe --status 2>&1
      $wslExit = $LASTEXITCODE
      $wslStatus | ForEach-Object {
        Log "wsl --status :: $($_.ToString())"
        Write-Host $_
      }

      if ($wslExit -eq 0) {
        $wslReady = $true
        Log "WSL is installed and responding normally."
      } else {
        Log "WSL executable exists but WSL is not fully installed/configured. Exit code: $wslExit" "WARN"
      }
    } catch {
      Log "WSL status check failed: $($_.Exception.Message)" "WARN"
    }
  }

  if (-not $wslReady) {
    Step-Start "Installing/configuring WSL2"

    if (-not $wslExe) {
      throw "wsl.exe could not be found. Windows WSL support may be unavailable."
    }

    try {
      & $wslExe --install --no-distribution 2>&1 | ForEach-Object {
        Log "wsl --install :: $($_.ToString())"
        Write-Host $_
      }

      $wslInstallExit = $LASTEXITCODE
      Log "wsl --install exit code: $wslInstallExit"

      if ($wslInstallExit -ne 0 -and $wslInstallExit -ne 3010) {
        throw "WSL installation returned exit code $wslInstallExit."
      }

      $State.WslInstalledByJAI = $true
      Save-State
      Step-End "Installing/configuring WSL2"

      if ($wslInstallExit -eq 3010 -or (Test-Pending-Reboot)) {
        Log "Windows restart is required before JAI can continue." "WARN"
        Write-Host ""
        Write-Host "RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "Restart Windows and run the same JAI command again." -ForegroundColor Yellow
        exit 3010
      }
    } catch {
      Log "WSL installation failed: $($_.Exception.Message)" "ERROR"
      throw
    }
  } else {
    Log "WSL already installed and healthy; skipping installation."
  }

  # Docker Desktop
  Refresh-Path
  $dockerDesktopExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  $dockerCli = Resolve-Tool "docker" @("$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe")

  if ($dockerCli) {
    Log "Docker CLI already installed and resolved to: $dockerCli; skipping WinGet."
  } elseif (Test-Path -LiteralPath $dockerDesktopExe) {
    Log "Docker Desktop is already installed but docker.exe is not on PATH. It will be resolved when Docker starts."
  } else {
    Step-Start "Installing Docker Desktop"

    Run-Command "winget Docker.DockerDesktop" {
      winget install --id Docker.DockerDesktop -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    }

    $State.DockerInstalledByJAI = $true
    Save-State
    Refresh-Path
    Step-End "Installing Docker Desktop"
  }

  # Repository
  Step-Start "Preparing JAI repository"

  if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    if (Test-Path $RepoDir) {
      Log "Removing incomplete repository directory: $RepoDir" "WARN"
      Remove-Item -Recurse -Force $RepoDir
    }

    Run-Command "git clone" {
      & $GitExe clone "https://github.com/$Repo.git" $RepoDir
    }
  } else {
    Run-Command "git fetch" {
      & $GitExe -C $RepoDir fetch --all --prune
    }
    Run-Command "git pull --ff-only" {
      & $GitExe -C $RepoDir pull --ff-only
    }
  }

  $commit = & $GitExe -C $RepoDir rev-parse HEAD
  $State.Commit = $commit
  Save-State
  Log "JAI source revision: $commit"
  Step-End "Preparing JAI repository"

  # Docker Engine
  Step-Start "Starting Docker Engine"

  if (-not (Wait-ForDocker 180)) {
    if (Test-Pending-Reboot) {
      Log "Windows restart appears required before Docker can start." "WARN"
      Write-Host ""
      Write-Host "RESTART REQUIRED" -ForegroundColor Yellow
      Write-Host "Restart Windows and run the same JAI command again." -ForegroundColor Yellow
      exit 3010
    }

    throw "Docker Engine did not become ready within 180 seconds. Start Docker Desktop and rerun JAI."
  }

  Step-End "Starting Docker Engine"

  # Infrastructure
  Step-Start "Configuring JAI infrastructure"

  Ensure-Compose-Env

  $compose = Join-Path $RepoDir "docker-compose.yml"
  if (-not (Test-Path -LiteralPath $compose)) {
    throw "docker-compose.yml is missing from the JAI repository."
  }

  Run-Command "docker compose config" {
    Push-Location $RepoDir
    try { docker compose config } finally { Pop-Location }
  }

  Run-Command "docker compose pull" {
    Push-Location $RepoDir
    try { docker compose pull } finally { Pop-Location }
  }

  Run-Command "docker compose up -d" {
    Push-Location $RepoDir
    try { docker compose up -d } finally { Pop-Location }
  }

  Run-Command "docker compose ps" {
    Push-Location $RepoDir
    try { docker compose ps } finally { Pop-Location }
  }

  Step-End "Configuring JAI infrastructure"

  Step-Start "Running JAI health check"
  $healthcheck = Join-Path $RepoDir "scripts\healthcheck.ps1"
  if (-not (Test-Path -LiteralPath $healthcheck)) {
    throw "JAI healthcheck script is missing."
  }
  Run-Command "JAI healthcheck" {
    & $healthcheck
  }
  Step-End "Running JAI health check"

  $elapsed = (Get-Date) - $StartTime
  Save-State
  Log "JAI bootstrap completed successfully in $([math]::Round($elapsed.TotalSeconds, 1)) seconds."

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
