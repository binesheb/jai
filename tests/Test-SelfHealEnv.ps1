$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "scripts/selfheal.ps1"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Self-heal script has PowerShell syntax errors." }
$functionAst = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Ensure-Compose-Env"
}, $true)
if ($null -eq $functionAst) { throw "Ensure-Compose-Env was not found." }
. ([scriptblock]::Create($functionAst.Extent.Text))
function Log([string]$Message, [string]$Level = "INFO") { }

$Repo = Join-Path ([System.IO.Path]::GetTempPath()) ("jai-env-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $Repo | Out-Null
try {
  $envFile = Join-Path $Repo ".env"
  @(
    "JAI_POSTGRES_PASSWORD='secret # part'"
    "JAI_POSTGRES_PASSWORD=replace-with-a-long-random-secret"
    "KEEP_SETTING=keep-me"
  ) | Set-Content -LiteralPath $envFile -Encoding UTF8

  if (-not (Ensure-Compose-Env)) { throw "Duplicate quoted password repair returned false." }
  $lines = @(Get-Content -LiteralPath $envFile)
  $passwordLines = @($lines | Where-Object { $_ -match '^[ \t]*JAI_POSTGRES_PASSWORD[ \t]*=' })
  if ($passwordLines.Count -ne 1) { throw "Duplicate password entries were not reduced to one." }
  if ($passwordLines[0] -cne "JAI_POSTGRES_PASSWORD='secret # part'") {
    throw "Quoted password value was not preserved exactly."
  }
  if ($lines -notcontains "KEEP_SETTING=keep-me") { throw "Unrelated .env setting was not preserved." }

  @(
    "JAI_POSTGRES_PASSWORD=replace-with-a-long-random-secret"
    "KEEP_SETTING=keep-me"
  ) | Set-Content -LiteralPath $envFile -Encoding UTF8
  if (-not (Ensure-Compose-Env)) { throw "Documented placeholder repair returned false." }
  $lines = @(Get-Content -LiteralPath $envFile)
  $passwordLines = @($lines | Where-Object { $_ -match '^[ \t]*JAI_POSTGRES_PASSWORD[ \t]*=' })
  if ($passwordLines.Count -ne 1) { throw "Placeholder repair did not produce exactly one password." }
  if ($passwordLines[0] -match 'replace-with-a-long-random-secret') {
    throw "Documented placeholder was incorrectly retained."
  }
  if ($lines -notcontains "KEEP_SETTING=keep-me") { throw "Unrelated .env setting was not preserved after placeholder repair." }

  Write-Host "[PASS] Quoted duplicate password preserved; documented placeholder replaced; unrelated settings retained."
}
finally {
  Remove-Item -LiteralPath $Repo -Recurse -Force -ErrorAction SilentlyContinue
}
