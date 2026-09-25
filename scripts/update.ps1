$ErrorActionPreference = "Stop"
git fetch --all --prune
git pull --ff-only
docker compose pull
docker compose up -d
& "$PSScriptRoot/healthcheck.ps1"
if ($LASTEXITCODE -ne 0) { Write-Error "JAI health check failed after update." }
