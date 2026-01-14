param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$versionHelperPath = Join-Path $scriptRoot 'helm-version-helpers.ps1'

if (-not (Test-Path $versionHelperPath)) {
    throw "Helm version helper not found at $versionHelperPath"
}

. $versionHelperPath
