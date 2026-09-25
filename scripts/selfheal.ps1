#requires -Version 5.1
param(
  [string]$IncidentLog = "",
  [string]$FailureSummary = "JAI automatic recovery was triggered."
)
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
function Get-GitHubToken {
  foreach($name in @("JAI_GITHUB_TOKEN","GH_TOKEN","GITHUB_TOKEN")){
    $v=[Environment]::GetEnvironmentVariable($name,"Process")
    if([string]::IsNullOrWhiteSpace($v)){ $v=[Environment]::GetEnvironmentVariable($name,"User") }
    if([string]::IsNullOrWhiteSpace($v)){ $v=[Environment]::GetEnvironmentVariable($name,"Machine") }
    if(-not [string]::IsNullOrWhiteSpace($v)){ return $v }
  }
  $gh=Get-Command gh -ErrorAction SilentlyContinue
  if($gh){ try { $v=& $gh.Source auth token 2>$null; if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($v)){ return ($v | Select-Object -First 1) } } catch {} }
  return $null
}
function Read-LogTail([string]$Path,[int]$MaxChars=45000) {
  if(-not(Test-Path $Path)){ return "(log file not found: $Path)" }
  $text=Get-Content $Path -Raw -ErrorAction SilentlyContinue
  if($null -eq $text){ return "(unable to read log file: $Path)" }
  if($text.Length -gt $MaxChars){ return "[log truncated]`n" + $text.Substring($text.Length-$MaxChars) }
  return $text
}
function Publish-GitHubIncident([bool]$Resolved) {
  $token=Get-GitHubToken
  if([string]::IsNullOrWhiteSpace($token)){ Log "GitHub incident publishing skipped: no token or gh authentication found." "WARN"; return }
  $headers=@{ Authorization="Bearer $token"; Accept="application/vnd.github+json"; "X-GitHub-Api-Version"="2022-11-28" }
  $status=if($Resolved){"RESOLVED"}else{"UNRESOLVED"}
  $title="JAI Auto-Recovery: $status - " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  $incident=Read-LogTail $IncidentLog
  $selfheal=Read-LogTail $Log
  $body="## JAI automatic incident report`n`n**Status:** $status`n**Host:** $env:COMPUTERNAME`n**User:** $env:USERNAME`n**Time:** $(Get-Date -Format o)`n`n### Failure summary`n$FailureSummary`n`n### Original bootstrap log`nPath: $IncidentLog`n`n```text`n$incident`n``` `n`n### Self-Heal log`nPath: $Log`n`n```text`n$selfheal`n``` `n`nThis issue was created automatically by JAI. No credentials are intentionally included in logs."
  try {
    $payload=@{title=$title;body=$body}|ConvertTo-Json -Depth 5
    $issue=Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/binesheb/jai/issues" -Headers $headers -Body $payload -ContentType "application/json"
    Log "GitHub incident issue created: #$($issue.number)"
    if($Resolved){
      $comment=@{body="JAI Self-Heal completed successfully. Final health check passed. This incident was automatically resolved."}|ConvertTo-Json
      Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/binesheb/jai/issues/$($issue.number)/comments" -Headers $headers -Body $comment -ContentType "application/json" | Out-Null
      $close=@{state="closed"}|ConvertTo-Json
      Invoke-RestMethod -Method Patch -Uri "https://api.github.com/repos/binesheb/jai/issues/$($issue.number)" -Headers $headers -Body $close -ContentType "application/json" | Out-Null
      Log "GitHub incident issue #$($issue.number) closed as resolved."
    }
  } catch { Log "GitHub incident publishing failed: $($_.Exception.Message)" "WARN" }
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

# Refresh JAI code first, but never discard local changes.
if(Test-Path (Join-Path $Repo ".git")){
  Push-Location $Repo
  try {
    Invoke-Step "Refreshing JAI source" {
      git fetch --all --prune
      git pull --ff-only
    } | Out-Null
  } finally { Pop-Location }
}

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
if($fixed){
  Publish-GitHubIncident $true
  exit 0
} else {
  Publish-GitHubIncident $false
  exit 1
}
