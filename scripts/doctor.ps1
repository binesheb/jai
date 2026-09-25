$ErrorActionPreference = "Continue"
$Root = Join-Path $env:ProgramData "JAI"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("doctor-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
function Check($Name,$Action) {
  try { & $Action; Write-Host "[OK] $Name" | Tee-Object -FilePath $Log -Append }
  catch { Write-Host "[FAIL] $Name :: $($_.Exception.Message)" | Tee-Object -FilePath $Log -Append }
}
Write-Host "JAI Doctor"
Check "Git" { git --version | Out-Null }
Check "WSL" { wsl --status | Out-Null }
Check "Docker" { docker version | Out-Null }
Check "Docker Compose" { docker compose version | Out-Null }
$env:Path = "$([Environment]::GetEnvironmentVariable("Path","Machine"));$([Environment]::GetEnvironmentVariable("Path","User"))"
$repo = Join-Path $Root "repo"
if (Test-Path (Join-Path $repo "docker-compose.yml")) {
  Push-Location $repo
  try { Check "Compose configuration" { docker compose config | Out-Null }; Check "Services" { docker compose ps | Out-Null } }
  finally { Pop-Location }
}
Write-Host "Doctor log: $Log"


Write-Host ""
Write-Host "Automatic repair is available. Running JAI Self-Heal..." -ForegroundColor Cyan
$selfHeal = Join-Path $Root "repo\scripts\selfheal.ps1"
if (Test-Path $selfHeal) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfHeal
  Write-Host "Self-Heal exit code: $LASTEXITCODE"
} else { Write-Host "[WARN] Self-Heal script is not installed yet." -ForegroundColor Yellow }
