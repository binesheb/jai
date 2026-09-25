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
  GitHubCliInstalledByJAI = $false
  GitHubAuthenticated = $false
  GitHubUser = $null
  WslDistro = $null
  IncidentIssueNumber = $null
  IncidentLog = $null
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
function Get-GitHubToken {
  foreach ($name in @("JAI_GITHUB_TOKEN","GH_TOKEN","GITHUB_TOKEN")) {
    $v = [Environment]::GetEnvironmentVariable($name,"Process")
    if ([string]::IsNullOrWhiteSpace($v)) { $v = [Environment]::GetEnvironmentVariable($name,"User") }
    if ([string]::IsNullOrWhiteSpace($v)) { $v = [Environment]::GetEnvironmentVariable($name,"Machine") }
    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
  }
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($gh) { try { $v = & $gh.Source auth token 2>$null; if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($v)) { return ($v | Select-Object -First 1) } } catch {} }
  return $null
}
function Ensure-GitHubAuthentication {
  Refresh-Path
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) {
    Step-Start "Installing GitHub CLI"
    Run-Command "winget GitHub.cli" { winget install --id GitHub.cli -e --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity }
    Refresh-Path
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { throw "GitHub CLI was not found after installation." }
    $State.GitHubCliInstalledByJAI = $true
    Save-State
    Step-End "Installing GitHub CLI"
  } else { Log "GitHub CLI already installed and resolved to: $($gh.Source)." }

  $authenticated = $false
  try { & $gh.Source auth status --hostname github.com 2>&1 | ForEach-Object { Log "gh auth status :: $($_.ToString())" }; $authenticated = ($LASTEXITCODE -eq 0) } catch { $authenticated = $false }

  if (-not $authenticated) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " JAI - GITHUB AUTHENTICATION" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "JAI will automatically start GitHub authentication so failed installations can report diagnostics and Self-Heal can update the same Issue." -ForegroundColor Yellow
    Write-Host "Complete the GitHub browser/device authorization when prompted." -ForegroundColor Yellow
    Write-Host "Set JAI_SKIP_GITHUB_AUTH=1 before installation if this machine must run without GitHub authentication." -ForegroundColor DarkGray
    Write-Host ""
    if ([Environment]::GetEnvironmentVariable("JAI_SKIP_GITHUB_AUTH","Process") -eq "1" -or [Environment]::GetEnvironmentVariable("JAI_SKIP_GITHUB_AUTH","User") -eq "1" -or [Environment]::GetEnvironmentVariable("JAI_SKIP_GITHUB_AUTH","Machine") -eq "1") {
      Log "JAI_SKIP_GITHUB_AUTH=1; skipping interactive GitHub authentication." "WARN"
    } else {
      Log "Starting automatic interactive GitHub CLI authentication."
      try {
        & $gh.Source auth login --hostname github.com --git-protocol https --web
        if ($LASTEXITCODE -ne 0) { throw "GitHub CLI authentication returned exit code $LASTEXITCODE." }
      } catch {
        Log "GitHub authentication failed: $($_.Exception.Message)" "WARN"
        Write-Host "GitHub authentication was not completed. JAI will continue without automatic incident reporting." -ForegroundColor Yellow
      }
    }
  }

  try { & $gh.Source auth status --hostname github.com 2>&1 | ForEach-Object { Log "gh auth status :: $($_.ToString())" }; $authenticated = ($LASTEXITCODE -eq 0) } catch { $authenticated = $false }
  if ($authenticated) {
    try {
      $user = (& $gh.Source api user --jq .login 2>$null | Select-Object -First 1)
      if (-not [string]::IsNullOrWhiteSpace($user)) { $State.GitHubUser = $user.Trim(); Log "GitHub authenticated as: $($State.GitHubUser)" }
      $repoAccess = (& $gh.Source api "repos/$Repo" --jq ".permissions.push" 2>$null | Select-Object -First 1)
      if ($repoAccess -eq "true") {
        $State.GitHubAuthenticated = $true
        Save-State
        Log "GitHub repository write access verified for $Repo."
        Write-Host "[OK] GitHub authentication and repository write access verified." -ForegroundColor Green
      } else {
        $State.GitHubAuthenticated = $false
        Save-State
        Log "GitHub login succeeded, but write access to $Repo could not be verified." "WARN"
        Write-Host "[WARN] GitHub login succeeded, but write access to $Repo was not verified." -ForegroundColor Yellow
      }
    } catch {
      $State.GitHubAuthenticated = $false; Save-State
      Log "GitHub access verification failed: $($_.Exception.Message)" "WARN"
    }
  } else {
    $State.GitHubAuthenticated = $false; Save-State
    Log "GitHub CLI is not authenticated. Continuing without GitHub incident reporting." "WARN"
  }
}
function Read-LogText([string]$Path,[int]$MaxChars=50000) {
  if (-not (Test-Path -LiteralPath $Path)) { return "(log file not found: $Path)" }
  $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
  if ($null -eq $text) { return "(unable to read log file: $Path)" }
  if ($text.Length -gt $MaxChars) { return "[log truncated]`n" + $text.Substring($text.Length-$MaxChars) }
  return $text
}
function Publish-Incident {
  param([string]$FailureSummary)
  $token = Get-GitHubToken
  if ([string]::IsNullOrWhiteSpace($token)) { Log "GitHub incident publishing skipped: no token or gh authentication found." "WARN"; return $false }
  $headers = @{ Authorization="Bearer $token"; Accept="application/vnd.github+json"; "X-GitHub-Api-Version"="2022-11-28" }
  $logPath = $Log
  $body = "## JAI automatic bootstrap incident`n`n**Status:** UNRESOLVED`n**Host:** $env:COMPUTERNAME`n**User:** $env:USERNAME`n**Time:** $(Get-Date -Format o)`n`n### Failure summary`n$FailureSummary`n`n### Bootstrap log`nPath: $logPath`n`n````text`n$(Read-LogText $logPath)`n```` `n`nThis issue was created automatically by JAI. The bootstrap log is retained locally until the incident is resolved."
  try {
    $payload = @{ title="JAI Bootstrap Incident - $env:COMPUTERNAME"; body=$body } | ConvertTo-Json -Depth 5
    $issue = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/issues" -Headers $headers -Body $payload -ContentType "application/json"
    $State.IncidentIssueNumber = $issue.number
    $State.IncidentLog = $Log
    Save-State
    Log "GitHub incident issue created: #$($issue.number)"
    return $true
  } catch { Log "GitHub incident publishing failed: $($_.Exception.Message)" "WARN"; return $false }
}

function Log([string]$Message, [string]$Level = "INFO") {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz') [$Level] $Message"
  $line | Tee-Object -FilePath $Log -Append
}

function Step-Start([string]$Name) {
  $script:Step++
  Log ("STEP {0} START: {1}" -f $script:Step, $Name)
  Write-Host ""
  Write-Host ("[{0}] {1}" -f $script:Step, $Name) -ForegroundColor Cyan
}

function Step-End([string]$Name) {
  Log ("STEP {0} COMPLETE: {1}" -f $script:Step, $Name)
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


function Get-RemoteCommitSha {
  try {
    $api = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$Repo/commits/main" -Headers @{ Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28" }
    if ($api.sha) { return [string]$api.sha }
  } catch {
    Log "Unable to query GitHub for the current commit SHA: $($_.Exception.Message)" "WARN"
  }
  return $null
}

function Install-RepositoryFromArchive {
  $tempRoot = Join-Path $env:TEMP ("jai-source-" + [guid]::NewGuid().ToString("N"))
  $zip = Join-Path $env:TEMP ("jai-source-" + [guid]::NewGuid().ToString("N") + ".zip")
  try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Log "Using GitHub source archive fallback because Git transport could not complete." "WARN"
    Run-With-Retry "GitHub source archive download" {
      Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/archive/refs/heads/main.zip" -OutFile $zip
      if (-not (Test-Path -LiteralPath $zip) -or (Get-Item -LiteralPath $zip).Length -lt 1024) {
        throw "GitHub source archive download was empty or incomplete."
      }
    } -Attempts 3 -DelaySeconds 5

    Expand-Archive -LiteralPath $zip -DestinationPath $tempRoot -Force
    $source = Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -First 1
    if (-not $source) { throw "GitHub source archive did not contain a repository directory." }

    if (Test-Path -LiteralPath $RepoDir) {
      $backup = "$RepoDir.archive-recovery-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
      Log "Moving failed repository checkout to $backup." "WARN"
      Move-Item -LiteralPath $RepoDir -Destination $backup -Force
    }

    Move-Item -LiteralPath $source.FullName -Destination $RepoDir -Force
    $remoteSha = Get-RemoteCommitSha
    if ($remoteSha) {
      $State.Commit = $remoteSha
      Log "Deployed source archive revision: $remoteSha"
    } else {
      Log "Source archive deployed, but the remote commit SHA could not be determined." "WARN"
    }
  } finally {
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
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
    $output = @(& $Command 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($item in $output) {
      $text = $item.ToString()
      Log "$Name :: $text"
      Write-Host $text
    }

    if ($exitCode -and $exitCode -ne 0) {
      throw "Exit code $exitCode"
    }

    Log "COMMAND COMPLETE: $Name"
  } catch {
    Log "COMMAND FAILED: $Name :: $($_.Exception.Message)" "ERROR"
    throw
  }
}

function Run-With-Retry([string]$Name, [scriptblock]$Command, [int]$Attempts = 3, [int]$DelaySeconds = 10) {
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      Log ("RETRYABLE COMMAND ATTEMPT {0}/{1}: {2}" -f $attempt, $Attempts, $Name)
      $output = @(& $Command 2>&1)
      $exitCode = $LASTEXITCODE

      foreach ($item in $output) {
        $text = $item.ToString()
        Log "$Name :: $text"
        Write-Host $text
      }

      if ($exitCode -and $exitCode -ne 0) {
        throw "Exit code $exitCode"
      }

      Log "RETRYABLE COMMAND COMPLETE: $Name"
      return
    } catch {
      Log "RETRYABLE COMMAND FAILED: $Name :: $($_.Exception.Message)" "WARN"
      if ($attempt -eq $Attempts) { throw }
      Log "Waiting $DelaySeconds seconds before retrying $Name." "WARN"
      Start-Sleep -Seconds $DelaySeconds
    }
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

  # GitHub CLI / incident reporting authentication
  Ensure-GitHubAuthentication

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

    try {
      Run-With-Retry "git clone" {
        & $GitExe -c http.version=HTTP/1.1 -c credential.interactive=never clone "https://github.com/$Repo.git" $RepoDir
      } -Attempts 2 -DelaySeconds 5
    } catch {
      Log "Git clone failed. Falling back to the GitHub source archive." "WARN"
      Install-RepositoryFromArchive
    }
  } else {
    # Existing checkout: recover automatically from stale locks, broken refs,
    # divergence, or a transient fetch failure before giving up.
    try {
      Run-With-Retry "git fetch" {
        & $GitExe -c http.version=HTTP/1.1 -c credential.interactive=never -C $RepoDir fetch origin main --prune
      } -Attempts 3 -DelaySeconds 5
    } catch {
      Log "Git fetch failed. Starting automatic repository recovery." "WARN"
      try {
        $gitStatus = @(& $GitExe -C $RepoDir status --porcelain=v1 -b 2>&1)
        foreach ($line in $gitStatus) { Log "git status :: $($line.ToString())" "WARN" }
        $gitHead = @(& $GitExe -C $RepoDir rev-parse --verify HEAD 2>&1)
        foreach ($line in $gitHead) { Log "git head :: $($line.ToString())" "WARN" }
      } catch {
        Log "Unable to collect Git diagnostics: $($_.Exception.Message)" "WARN"
      }
      $lockFiles = @(
        (Join-Path $RepoDir ".git\index.lock"),
        (Join-Path $RepoDir ".git\packed-refs.lock"),
        (Join-Path $RepoDir ".git\FETCH_HEAD.lock"),
        (Join-Path $RepoDir ".git\refs\remotes\origin\main.lock")
      )
      foreach ($lock in $lockFiles) {
        if (Test-Path $lock) {
          Log "Removing stale Git lock: $lock" "WARN"
          Remove-Item -Force $lock -ErrorAction SilentlyContinue
        }
      }

      Run-Command "git remote repair" {
        & $GitExe -C $RepoDir remote set-url origin "https://github.com/$Repo.git"
      }

      try {
        Run-Command "git fsck" {
          & $GitExe -C $RepoDir fsck --full
        }
      } catch {
        Log "Git fsck reported repository problems; attempting clean re-clone." "WARN"
      }

      try {
        Run-With-Retry "git fetch recovery" {
          & $GitExe -C $RepoDir fetch origin main --prune
        } -Attempts 2 -DelaySeconds 5
      } catch {
        $backup = "$RepoDir.recovery-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Log "Repository recovery fetch failed. Moving checkout to $backup and cloning clean." "WARN"
        Move-Item -LiteralPath $RepoDir -Destination $backup -Force
        try {
          Run-With-Retry "git clean clone" {
            & $GitExe clone "https://github.com/$Repo.git" $RepoDir
          } -Attempts 2 -DelaySeconds 5
        } catch {
          Log "Clean Git clone failed. Falling back to the GitHub source archive." "WARN"
          Install-RepositoryFromArchive
        }
      }
    }

    # The installer is authoritative: deploy the repository's current main branch.
    # Archive fallback deployments intentionally have no .git directory, so they
    # must not be sent through Git checkout/reset commands.
    if (Test-Path -LiteralPath (Join-Path $RepoDir ".git")) {
      Run-Command "git checkout main" {
        & $GitExe -C $RepoDir checkout -B main origin/main
      }
      Run-Command "git reset --hard origin/main" {
        & $GitExe -C $RepoDir reset --hard origin/main
      }
    } else {
      Log "Repository was deployed from the GitHub source archive; skipping Git checkout/reset."
    }
  }

  if (Test-Path -LiteralPath (Join-Path $RepoDir ".git")) {
    $commit = (& $GitExe -C $RepoDir rev-parse HEAD | Select-Object -First 1).ToString().Trim()
  } else {
    $commit = Get-RemoteCommitSha
  }
  if (-not [string]::IsNullOrWhiteSpace($commit)) {
    $State.Commit = $commit
    Save-State
    Log "JAI source revision: $commit"
  } else {
    Log "JAI source revision could not be determined." "WARN"
  }
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

  try {
    Run-With-Retry "docker compose pull" {
      Push-Location $RepoDir
      try { docker compose pull } finally { Pop-Location }
    } 4 15
  } catch {
    Log "Docker image pull still failing after normal retries. Starting JAI Self-Heal." "WARN"
    $selfHeal = Join-Path $RepoDir "scripts\selfheal.ps1"
    if (Test-Path -LiteralPath $selfHeal) {
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfHeal -IncidentLog $Log -FailureSummary "Docker image pull failed after automatic retries."
      if ($LASTEXITCODE -ne 0) {
        throw "Docker image pull failed and JAI Self-Heal could not fully recover the environment."
      }
    } else {
      throw
    }
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
  Write-Host "Repository: $RepoDir"
  Write-Host "Infrastructure: Docker Compose services started."
  Write-Host "Installation log cleared because bootstrap completed successfully." -ForegroundColor Green
  Remove-Item -LiteralPath $Log -Force -ErrorAction SilentlyContinue
} catch {
  Log "JAI bootstrap FAILED: $($_.Exception.Message)" "ERROR"
  Log "Stack: $($_.ScriptStackTrace)" "ERROR"
  Publish-Incident -FailureSummary $_.Exception.Message | Out-Null
  Write-Host ""
  Write-Host "JAI bootstrap FAILED. Attempting automatic recovery..." -ForegroundColor Yellow
  $selfHeal = Join-Path $RepoDir "scripts\selfheal.ps1"
  if (Test-Path -LiteralPath $selfHeal) {
    Log "Launching JAI Self-Heal after bootstrap failure."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfHeal
    $healExit = $LASTEXITCODE
    if ($healExit -eq 0) {
      Log "JAI Self-Heal repaired the environment." "INFO"
      Write-Host "JAI Self-Heal repaired the environment. Rerun the same JAI command to complete bootstrap." -ForegroundColor Green
      Write-Host "Self-heal log: $LogDir" -ForegroundColor Yellow
      exit 0
    }
    Log "JAI Self-Heal exit code: $healExit" "WARN"
  }
  Write-Host "Detailed log: $Log" -ForegroundColor Yellow
  Write-Host "JAI Self-Heal log is also stored under C:\ProgramData\JAI\logs\"
  exit 1
}
