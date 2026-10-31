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
    "JAI_POSTGRES_PASSWORD='secret # part' # preserve this comment"
    "JAI_POSTGRES_PASSWORD=replace-with-a-long-random-secret"
    "KEEP_SETTING=keep-me"
  ) | Set-Content -LiteralPath $envFile -Encoding UTF8

  if (-not (Ensure-Compose-Env)) { throw "Duplicate quoted password repair returned false." }
  $lines = @(Get-Content -LiteralPath $envFile)
  $passwordLines = @($lines | Where-Object { $_ -match '^[ \t]*JAI_POSTGRES_PASSWORD[ \t]*[:=]' })
  if ($passwordLines.Count -ne 1) { throw "Duplicate password entries were not reduced to one." }
  if ($passwordLines[0] -cne "JAI_POSTGRES_PASSWORD='secret # part' # preserve this comment") {
    throw "Quoted password value was not preserved exactly."
  }
  if ($lines -notcontains "KEEP_SETTING=keep-me") { throw "Unrelated .env setting was not preserved." }

  @(
    "JAI_POSTGRES_PASSWORD= # intentionally blank"
    "KEEP_SETTING=keep-me"
  ) | Set-Content -LiteralPath $envFile -Encoding UTF8
  if (-not (Ensure-Compose-Env)) { throw "Comment-only password repair returned false." }
  $lines = @(Get-Content -LiteralPath $envFile)
  $passwordLines = @($lines | Where-Object { $_ -match '^[ \t]*JAI_POSTGRES_PASSWORD[ \t]*[:=]' })
  if ($passwordLines.Count -ne 1 -or $passwordLines[0] -match '[:=][ \t]*(#|$)') {
    throw "Comment-only value was incorrectly accepted as a password."
  }
  if ($lines -notcontains "KEEP_SETTING=keep-me") { throw "Unrelated setting was not preserved after comment-only repair." }

  @("JAI_POSTGRES_PASSWORD: legacy-secret") | Set-Content -LiteralPath $envFile -Encoding UTF8
  if (-not (Ensure-Compose-Env)) { throw "Colon-delimited password was not recognized." }
  $lines = @(Get-Content -LiteralPath $envFile)
  if ($lines.Count -ne 1 -or $lines[0] -cne "JAI_POSTGRES_PASSWORD: legacy-secret") {
    throw "Colon-delimited password was not preserved."
  }

  @("JAI_POSTGRES_PASSWORD=legacy-secret'") | Set-Content -LiteralPath $envFile -Encoding UTF8
  if (-not (Ensure-Compose-Env)) { throw "Unquoted password ending in a quote was incorrectly rejected." }
  $lines = @(Get-Content -LiteralPath $envFile)
  if ($lines.Count -ne 1 -or $lines[0] -cne "JAI_POSTGRES_PASSWORD=legacy-secret'") {
    throw "Unquoted trailing quote was not preserved as a literal."
  }

  $ambiguous = 'JAI_POSTGRES_PASSWORD=$MISSING'
  Set-Content -LiteralPath $envFile -Value $ambiguous -Encoding UTF8
  if (Ensure-Compose-Env) { throw "Unresolved interpolation was incorrectly accepted." }
  $lines = @(Get-Content -LiteralPath $envFile)
  if ($lines.Count -ne 1 -or $lines[0] -cne $ambiguous) {
    throw "Ambiguous interpolation was modified instead of failing closed."
  }

  Write-Host "[PASS] Quoted duplicate, comment-only, colon delimiter, trailing quote, and unresolved interpolation cases."
}
finally {
  Remove-Item -LiteralPath $Repo -Recurse -Force -ErrorAction SilentlyContinue
}
