$ErrorActionPreference = "Stop"
$Root = Join-Path $env:ProgramData "JAI"
$Repo = Join-Path $Root "repo"
if (-not (Test-Path (Join-Path $Repo ".git"))) { throw "JAI repository not found at $Repo. Run the installer first." }
$env:Path = "$([Environment]::GetEnvironmentVariable("Path","Machine"));$([Environment]::GetEnvironmentVariable("Path","User"))"
Push-Location $Repo
try {
  git fetch --all --prune
  git pull --ff-only
  docker compose pull
  docker compose up -d
  & "$Repo\scripts\healthcheck.ps1"
  if ($LASTEXITCODE -ne 0) { throw "JAI health check failed after update." }
} finally { Pop-Location }
