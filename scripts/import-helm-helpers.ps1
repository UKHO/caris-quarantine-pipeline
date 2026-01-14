param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersPath = Join-Path $scriptRoot 'helm-helpers.ps1'

if (-not (Test-Path $helpersPath)) {
    throw "Helm helper script not found at $helpersPath"
}

. $helpersPath
