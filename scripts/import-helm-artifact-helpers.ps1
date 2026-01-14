param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$artifactHelperPath = Join-Path $scriptRoot 'helm-artifact-helpers.ps1'

if (-not (Test-Path $artifactHelperPath)) {
    throw "Helm artifact helper not found at $artifactHelperPath"
}

. $artifactHelperPath
