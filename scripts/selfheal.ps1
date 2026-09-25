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
$script:StateFile = Join-Path $Root "installation-state.json"
$script:State = $null
if(Test-Path -LiteralPath $script:StateFile){ try { $script:State=Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json } catch {} }
if([string]::IsNullOrWhiteSpace($IncidentLog) -and $script:State -and $script:State.IncidentLog){ $IncidentLog=$script:State.IncidentLog }
if([string]::IsNullOrWhiteSpace($IncidentLog)){
  $latest=Get-ChildItem -LiteralPath $LogDir -Filter "install-*.log" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($latest){ $IncidentLog=$latest.FullName }
}

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
    $v=[Environment]::GetEnvironmentVariable($name,"Process"); if([string]::IsNullOrWhiteSpace($v)){ $v=[Environment]::GetEnvironmentVariable($name,"User") }; if([string]::IsNullOrWhiteSpace($v)){ $v=[Environment]::GetEnvironmentVariable($name,"Machine") }; if(-not [string]::IsNullOrWhiteSpace($v)){ return $v }
  }
  $gh=Get-Command gh -ErrorAction SilentlyContinue; if($gh){ try { $v=& $gh.Source auth token 2>$null; if($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($v)){ return ($v | Select-Object -First 1) } } catch {} }
  return $null
}
function Read-LogTail([string]$Path,[int]$MaxChars=45000){ if(-not(Test-Path -LiteralPath $Path)){ return "(log file not found: $Path)" }; $text=Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue; if($null -eq $text){ return "(unable to read log file: $Path)" }; if($text.Length -gt $MaxChars){ return "[log truncated]`n"+$text.Substring($text.Length-$MaxChars) }; return $text }
function Ensure-Compose-Env {
  $envFile=Join-Path $Repo ".env"
  if(Test-Path -LiteralPath $envFile){ Log "Existing local .env found; preserving it."; return $true }
  $bytes=New-Object byte[] 32
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
  $password=[Convert]::ToBase64String($bytes).Replace("+","-").Replace("/","_").Replace("=","")
  @(
    "JAI_POSTGRES_DB=jai"
    "JAI_POSTGRES_USER=jai"
    "JAI_POSTGRES_PASSWORD=$password"
    "JAI_POSTGRES_PORT=5432"
    "JAI_REDIS_PORT=6379"
  ) | Set-Content -LiteralPath $envFile -Encoding UTF8
  Log "Created missing local JAI .env with a generated PostgreSQL password."
  return $true
}
function Save-State { if($script:State){ $script:State | ConvertTo-Json | Set-Content -LiteralPath $script:StateFile -Encoding UTF8 } }
function Get-OpenIncident {
  $token=Get-GitHubToken; if([string]::IsNullOrWhiteSpace($token)){ return $null }
  $headers=@{Authorization="Bearer $token";Accept="application/vnd.github+json";"X-GitHub-Api-Version"="2022-11-28"}
  try {
    $items=Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/binesheb/jai/issues?state=open&per_page=50" -Headers $headers
    $title="JAI Bootstrap Incident - $env:COMPUTERNAME"
    return ($items | Where-Object { $_.pull_request -eq $null -and $_.title -eq $title } | Select-Object -First 1)
  } catch { Log "GitHub incident lookup failed: $($_.Exception.Message)" "WARN"; return $null }
}
function Publish-LogToGitHub([string]$LocalPath) {
  if (-not (Test-Path -LiteralPath $LocalPath)) { return $null }
  $token=Get-GitHubToken
  if([string]::IsNullOrWhiteSpace($token)){ Log "GitHub log upload skipped: no token." "WARN"; return $null }
  $headers=@{Authorization="Bearer $token";Accept="application/vnd.github+json";"X-GitHub-Api-Version"="2022-11-28"}
  try {
    $name=Split-Path -Leaf $LocalPath
    $remotePath="logs/incidents/$env:COMPUTERNAME/$name"
    $raw=Get-Content -LiteralPath $LocalPath -Raw -ErrorAction Stop
    $safe=[regex]::Replace($raw,'(?im)(authorization\s*:\s*bearer\s+)[^\s]+','$1[REDACTED]')
    $safe=[regex]::Replace($safe,'(?im)((?:password|passwd|secret|token|api[_-]?key)\s*[=:]\s*)[^\s]+','$1[REDACTED]')
    $content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($safe))
    $uri="https://api.github.com/repos/$Repo/contents/$remotePath"
    $existing=$null
    try{$existing=Invoke-RestMethod -Method Get -Uri ($uri+"?ref=main") -Headers $headers}catch{}
    $payload=@{message="chore: upload JAI log $name";content=$content;branch="main"}
    if($existing -and $existing.sha){$payload.sha=$existing.sha}
    $result=Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body ($payload|ConvertTo-Json -Depth 5) -ContentType "application/json"
    Log "JAI log uploaded to GitHub: $remotePath"
    return @{Path=$remotePath;HtmlUrl=$result.content.html_url;DownloadUrl="https://raw.githubusercontent.com/$Repo/main/$remotePath"}
  } catch { Log "GitHub log upload failed for $LocalPath : $($_.Exception.Message)" "WARN"; return $null }
}
function Publish-LogsForIncident([string]$IncidentLogPath) {
  $results=@()
  if(-not(Test-Path -LiteralPath $IncidentLogPath)){ return $results }
  $result=Publish-LogToGitHub $IncidentLogPath
  if($result){ $results += $result }
  return $results
}
function Finalize-ResolvedGitHubLogs([int]$IssueNumber) {
  $token=Get-GitHubToken
  if([string]::IsNullOrWhiteSpace($token)){ Log "GitHub resolved-log cleanup skipped: no token." "WARN"; return }
  $headers=@{Authorization="Bearer $token";Accept="application/vnd.github+json";"X-GitHub-Api-Version"="2022-11-28"}
  $base="logs/incidents/$env:COMPUTERNAME"
  try {
    $items=Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$Repo/contents/$base?ref=main" -Headers $headers
    $logs=@($items | Where-Object { $_.type -eq "file" -and $_.name -like "*.log" })
    foreach($item in $logs){
      try {
        $payload=@{message="chore: remove resolved raw JAI log $($item.name)";sha=$item.sha;branch="main"}|ConvertTo-Json
        Invoke-RestMethod -Method Delete -Uri $item.url -Headers $headers -Body $payload -ContentType "application/json" | Out-Null
        Log "Removed resolved raw GitHub log: $($item.path)"
      } catch { Log "Could not remove resolved GitHub log $($item.path): $($_.Exception.Message)" "WARN" }
    }
    $summaryName="resolved-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))-issue-$IssueNumber.md"
    $summaryPath="$base/$summaryName"
    $summary=@"
# JAI Incident Resolution

- Host: $env:COMPUTERNAME
- Issue: #$IssueNumber
- Resolved: $((Get-Date).ToUniversalTime().ToString("o"))
- Status: health check passed
- Raw diagnostic logs: removed after resolution
- Detailed diagnosis: recorded on GitHub Issue #$IssueNumber

This file is intentionally a minimal audit marker. Raw logs are not retained after successful resolution.
"@
    $payload=@{message="chore: record resolved JAI incident #$IssueNumber";content=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($summary));branch="main"}|ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Put -Uri "https://api.github.com/repos/$Repo/contents/$summaryPath" -Headers $headers -Body $payload -ContentType "application/json" | Out-Null
    Log "Created minimal resolved-incident audit marker: $summaryPath"
  } catch { Log "Resolved GitHub log finalization failed: $($_.Exception.Message)" "WARN" }
}

function Remove-LogFromGitHub([string]$LocalPath) {
  if([string]::IsNullOrWhiteSpace($LocalPath)){ return }
  $token=Get-GitHubToken
  if([string]::IsNullOrWhiteSpace($token)){ return }
  $headers=@{Authorization="Bearer $token";Accept="application/vnd.github+json";"X-GitHub-Api-Version"="2022-11-28"}
  try {
    $name=Split-Path -Leaf $LocalPath
    $remotePath="logs/incidents/$env:COMPUTERNAME/$name"
    $uri="https://api.github.com/repos/binesheb/jai/contents/$remotePath?ref=main"
    $file=Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    $payload=@{message="chore: remove resolved JAI incident log $name";sha=$file.sha;branch="main"}|ConvertTo-Json
    Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/binesheb/jai/contents/$remotePath" -Headers $headers -Body $payload -ContentType "application/json" | Out-Null
    Log "Resolved incident log removed from GitHub: $remotePath"
  } catch { Log "GitHub incident log cleanup failed for $LocalPath : $($_.Exception.Message)" "WARN" }
}

function Publish-GitHubIncident([bool]$Resolved) {
  $token=Get-GitHubToken; if([string]::IsNullOrWhiteSpace($token)){ Log "GitHub incident publishing skipped: no token or gh authentication found." "WARN"; return }
  $headers=@{Authorization="Bearer $token";Accept="application/vnd.github+json";"X-GitHub-Api-Version"="2022-11-28"}
  $issue=$null
  if($script:State -and $script:State.IncidentIssueNumber){
    try {
      $issue=Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/binesheb/jai/issues/$($script:State.IncidentIssueNumber)" -Headers $headers
      if($issue.state -ne "open" -or $issue.pull_request){ $issue=$null }
    } catch { $issue=$null }
  }
  if(-not $issue){ $issue=Get-OpenIncident }
  if(-not (Test-Path -LiteralPath $IncidentLog)){ $IncidentLog=$Log }
  $uploadedLogs=@(Publish-LogsForIncident $IncidentLog)
  $selfHealUpload = Publish-LogToGitHub $Log
  if($selfHealUpload){ Log "Self-Heal log uploaded to GitHub: $($selfHealUpload.Path)" }
  $incident=Read-LogTail $IncidentLog
  $incidentLinks = $uploadedLogs | ForEach-Object { "[GitHub log]($($_.HtmlUrl)) — raw: $($_.DownloadUrl)" } | Out-String
  if(-not $Resolved -and -not $issue){
    $body="## JAI automatic incident report`n`n**Status:** UNRESOLVED`n**Host:** $env:COMPUTERNAME`n**User:** $env:USERNAME`n**Time:** $(Get-Date -Format o)`n`n### GitHub logs`n$incidentLinks`n### Failure summary`n$FailureSummary`n`n### Bootstrap log`nPath: $IncidentLog`n`n````text`n$incident`n```` `n`n### Self-Heal log`nPath: $Log`n`n````text`n$(Read-LogTail $Log)`n```` `n`nThis issue was created automatically by JAI. Logs are retained locally until the incident is resolved."
    try { $payload=@{title="JAI Bootstrap Incident - $env:COMPUTERNAME";body=$body}|ConvertTo-Json -Depth 5; $issue=Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/binesheb/jai/issues" -Headers $headers -Body $payload -ContentType "application/json"; $script:State.IncidentIssueNumber=$issue.number; $script:State.IncidentLog=$IncidentLog; Save-State; Log "GitHub incident issue created: #$($issue.number)" } catch { Log "GitHub incident publishing failed: $($_.Exception.Message)" "WARN"; return }
  }
  if($Resolved -and $issue){
    try {
      $comment=@{body="JAI Self-Heal completed successfully. Final health check passed. The failure described in the attached logs has been cleared. All generated resolution checklist items are being marked complete."}|ConvertTo-Json
      Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/binesheb/jai/issues/$($issue.number)/comments" -Headers $headers -Body $comment -ContentType "application/json" | Out-Null
      $current=Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/binesheb/jai/issues/$($issue.number)" -Headers $headers
      $body=$current.body
      if($body){ $body=[regex]::Replace($body,"(?m)^- \[ \] ","- [x] ") }
      $update=@{body=$body;state="closed";state_reason="completed"}|ConvertTo-Json -Depth 5
      Invoke-RestMethod -Method Patch -Uri "https://api.github.com/repos/binesheb/jai/issues/$($issue.number)" -Headers $headers -Body $update -ContentType "application/json" | Out-Null
      Log "GitHub incident issue #$($issue.number) checklist completed and issue closed as resolved."
    } catch { Log "GitHub incident resolution failed: $($_.Exception.Message)" "WARN"; return }
    $logsToRemove=@($IncidentLog,$Log) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach($p in $logsToRemove){ Log "Resolved incident log scheduled for cleanup: $p" }
    $script:State.IncidentIssueNumber=$null; $script:State.IncidentLog=$null; Save-State
    Finalize-ResolvedGitHubLogs $issue.number
    foreach($p in $logsToRemove){ Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
  } elseif(-not $Resolved -and $issue){
    try { $comment=@{body="JAI Self-Heal ran again but the environment is still not healthy.`n`nLatest GitHub logs:`n$incidentLinks"}|ConvertTo-Json; Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/binesheb/jai/issues/$($issue.number)/comments" -Headers $headers -Body $comment -ContentType "application/json" | Out-Null } catch { Log "GitHub incident update failed: $($_.Exception.Message)" "WARN" }
  }
}
function Refresh-RepositoryFromArchive {
  $tempRoot = Join-Path $env:TEMP ("jai-selfheal-" + [guid]::NewGuid().ToString("N"))
  $zip = Join-Path $env:TEMP ("jai-selfheal-" + [guid]::NewGuid().ToString("N") + ".zip")
  try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Log "Git transport failed. Falling back to the GitHub source archive." "WARN"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/binesheb/jai/archive/refs/heads/main.zip" -OutFile $zip
    if(-not(Test-Path -LiteralPath $zip) -or (Get-Item -LiteralPath $zip).Length -lt 1024){
      throw "GitHub source archive download was empty or incomplete."
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $tempRoot -Force
    $source=Get-ChildItem -LiteralPath $tempRoot -Directory | Select-Object -First 1
    if(-not $source){ throw "GitHub source archive did not contain a repository directory." }
    Log "Refreshing working tree from GitHub source archive."
    & robocopy $source.FullName $Repo /E /XD ".git" ".github" /R:2 /W:2 /NFL /NDL /NJH /NJS /NP 2>&1 | ForEach-Object { Log "archive refresh :: $($_.ToString())" }
    if($LASTEXITCODE -gt 7){ throw "robocopy returned exit code $LASTEXITCODE" }
    Log "Repository source refreshed from GitHub archive."
    return $true
  } catch {
    Log "GitHub source archive recovery failed: $($_.Exception.Message)" "WARN"
    return $false
  } finally {
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
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
  $exe=(Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe")
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
    if(-not (Invoke-Step "Refreshing JAI source" {
      git -c http.version=HTTP/1.1 -c credential.interactive=never fetch --all --prune
      git -c http.version=HTTP/1.1 -c credential.interactive=never pull --ff-only
    })){
      if(Refresh-RepositoryFromArchive){ $fixed=$true }
    }
  } finally { Pop-Location }
}

Refresh-Path
if(-not(Docker-Ready)){
  if(Invoke-Step "Restarting Docker Desktop" {
    $p=Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if($p){ $p | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep 3 }
    $exe=Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
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
  Ensure-Compose-Env | Out-Null
  Push-Location $Repo
  try {
    Invoke-Step "Checking Docker engine" { docker info } | Out-Null
    for($i=1;$i-le 3;$i++){
      if(Invoke-Step "Pulling JAI images (attempt $i/3)" { docker compose --progress plain pull }){ $fixed=$true; break }
      Start-Sleep (10*$i)
    }
    if(Invoke-Step "Recreating JAI services" { docker compose up -d --remove-orphans }){ $fixed=$true }
  } finally { Pop-Location }
}

$health=Join-Path $Repo "scripts\healthcheck.ps1"
$healthPassed=$false
if(Test-Path $health){
  & $health
  if($LASTEXITCODE -eq 0){
    Log "SELF-HEAL SUCCESS: JAI health check passed."
    $healthPassed=$true
  } else {
    Log "SELF-HEAL could not fully repair JAI. Manual diagnosis may be required." "WARN"
  }
}
if($healthPassed){
  Publish-GitHubIncident $true
  exit 0
} elseif($fixed){
  Publish-GitHubIncident $false
  exit 2
} else {
  Publish-GitHubIncident $false
  exit 1
}
