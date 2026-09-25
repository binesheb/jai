$ErrorActionPreference = "Stop"
Write-Host "JAI health check"
docker version | Out-Host
docker compose ps | Out-Host
foreach ($service in @("postgres","redis")) {
  $state = docker compose ps --format json $service 2>$null
  if (-not $state) { Write-Warning "$service is not running." }
}
Write-Host "Health check complete."
