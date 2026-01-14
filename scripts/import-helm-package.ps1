param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageHelper = Join-Path $scriptRoot 'helm-package.ps1'

if (-not (Test-Path $packageHelper)) {
    throw "Helm package helper not found at $packageHelper"
}

. $packageHelper
