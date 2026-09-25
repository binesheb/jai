$ErrorActionPreference = "Stop"
Write-Host "JAI bootstrap - Windows"
function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { Write-Error "$name is not installed or not on PATH." }
}
Require-Command git
Require-Command docker
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { wsl --status } else { Write-Warning "WSL2 is not installed." }
Write-Host "Prerequisite check complete."
