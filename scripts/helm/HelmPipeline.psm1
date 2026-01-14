Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

function Resolve-HelmPipelineScriptPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $candidate = Join-Path (Join-Path $PSScriptRoot '..') $RelativePath
    if (-not (Test-Path $candidate)) {
        throw "Required Helm pipeline script not found at $candidate"
    }

    return (Resolve-Path $candidate).Path
}

. (Resolve-HelmPipelineScriptPath 'helm-helpers.ps1')
. (Resolve-HelmPipelineScriptPath 'helm-package.ps1')
. (Resolve-HelmPipelineScriptPath 'helm-chart-helpers.ps1')
. (Resolve-HelmPipelineScriptPath 'helm-version-helpers.ps1')
. (Resolve-HelmPipelineScriptPath 'helm-artifact-helpers.ps1')

Export-ModuleMember -Function @(
    'Get-AcrAccessToken',
    'Invoke-HelmRegistryCommand',
    'Invoke-HelmRegistryPull',
    'Invoke-HelmRegistryPush',
    'Invoke-HelmPackage',
    'Expand-HelmChartArchive',
    'Get-HelmChartVersion',
    'Set-HelmChartVersion',
    'Get-HelmChartVersionFromManifest',
    'Get-HelmChartArchivePath'
)
