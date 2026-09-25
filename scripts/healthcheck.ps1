#requires -Version 5.1
$ErrorActionPreference = "Continue"
$Root = Join-Path $env:ProgramData "JAI"
$Repo = Join-Path $Root "repo"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("health-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
function Log([string]$m,[string]$l="INFO"){ "$(Get-Date -Format o) [$l] $m" | Tee-Object -FilePath $Log -Append }
$failed=$false
function Check([string]$name,[scriptblock]$action){
  try {
    & $action 2>&1 | ForEach-Object { Log "$name :: $($_.ToString())" }
    if($LASTEXITCODE -and $LASTEXITCODE -ne 0){ throw "Exit code $LASTEXITCODE" }
    Log "$name: OK"
  } catch { Log "$name: FAIL :: $($_.Exception.Message)" "ERROR"; $script:failed=$true }
}
Log "JAI health check started."
$env:Path = "$([Environment]::GetEnvironmentVariable("Path","Machine"));$([Environment]::GetEnvironmentVariable("Path","User"))"
Check "Git" { git --version }
Check "WSL" { wsl --status }
Check "Docker" { docker version }
Check "Docker Compose" { docker compose version }
if(Test-Path (Join-Path $Repo "docker-compose.yml")){
  Push-Location $Repo
  try { Check "Compose config" { docker compose config }; Check "Services" { docker compose ps } }
  finally { Pop-Location }
}
if($failed){ Log "JAI health check FAILED." "ERROR"; Write-Host "JAI health check FAILED. Log: $Log" -ForegroundColor Red; exit 1 }
Log "JAI health check PASSED."
Write-Host "JAI health check PASSED. Log: $Log" -ForegroundColor Green
