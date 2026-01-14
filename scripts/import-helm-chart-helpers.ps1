param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$chartHelperPath = Join-Path $scriptRoot 'helm-chart-helpers.ps1'

if (-not (Test-Path $chartHelperPath)) {
    throw "Helm chart helper not found at $chartHelperPath"
}

. $chartHelperPath
