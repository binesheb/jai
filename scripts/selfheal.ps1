#requires -Version 5.1
$ErrorActionPreference = "Continue"
$Root = Join-Path $env:ProgramData "JAI"
$Repo = Join-Path $Root "repo"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("selfheal-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

function Log([string]$Message,[string]$Level="INFO") {
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff zzz') [$Level] $Message" | Tee-Object -FilePath $Log -Append
}
function Invoke-Step([string]$Name,[scriptblock]$Action) {
  Log "REPAIR START: $Name"
  try {
    & $Action 2>&1 | ForEach-Object { Log "$Name :: $($_.ToString())"; Write-Host $_ }
    if($LASTEXITCODE -and $LASTEXITCODE -ne 0){ throw "Exit code $LASTEXITCODE" }
    Log "REPAIR COMPLETE: $Name"
    return $true
  } catch {
    Log "REPAIR FAILED: $Name :: $($_.Exception.Message)" "WARN"
    return $false
  }
}
function Refresh-Path {
  $env:Path="$([Environment]::GetEnvironmentVariable('Path','Machine'));$([Environment]::GetEnvironmentVariable('Path','User'))"
}
function Docker-Ready {
  try { docker version --format '{{.Server.Version}}' *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}
function Start-Docker {
  Refresh-Path
  $exe="$env:ProgramFilesDockerDockerDocker Desktop.exe"
  if(Test-Path $exe) {
    if(-not(Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue)){ Start-Process $exe }
    for($i=0;$i-lt 36;$i++){ if(Docker-Ready){ return $true }; Start-Sleep 5 }
  }
  return (Docker-Ready)
}

Log "JAI Self-Heal started."
Log "Host: $env:COMPUTERNAME"
Log "Repository: $Repo"
$fixed=$false

Refresh-Path
if(-not(Docker-Ready)){
  if(Invoke-Step "Restarting Docker Desktop" {
    $p=Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if($p){ $p | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep 3 }
    $exe="$env:ProgramFilesDockerDockerDocker Desktop.exe"
    if(-not(Test-Path $exe)){ throw "Docker Desktop executable not found." }
    Start-Process $exe
    Start-Sleep 10
  }) { $fixed=$true }
  if(-not(Docker-Ready)){ Start-Docker | Out-Null }
}

try {
  & wsl --status *> $null
  if($LASTEXITCODE -ne 0){
    Invoke-Step "Restarting WSL" { wsl --shutdown; Start-Sleep 5 } | Out-Null
    Start-Docker | Out-Null
    $fixed=$true
  }
} catch {}

if(Docker-Ready -and (Test-Path (Join-Path $Repo "docker-compose.yml"))){
  Push-Location $Repo
  try {
    Invoke-Step "Checking Docker engine" { docker info } | Out-Null
    for($i=1;$i-le 3;$i++){
      if(Invoke-Step "Pulling JAI images (attempt $i/3)" { docker compose pull }){ $fixed=$true; break }
      Start-Sleep (10*$i)
    }
    if(Invoke-Step "Recreating JAI services" { docker compose up -d --remove-orphans }){ $fixed=$true }
  } finally { Pop-Location }
}

$health=Join-Path $Repo "scriptshealthcheck.ps1"
if(Test-Path $health){
  & $health
  if($LASTEXITCODE -eq 0){ Log "SELF-HEAL SUCCESS: JAI health check passed."; exit 0 }
  Log "SELF-HEAL could not fully repair JAI. Manual diagnosis may be required." "WARN"
}
if($fixed){ exit 2 } else { exit 1 }
