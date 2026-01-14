function Get-HelmChartArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchDirectory,

        [string]$ErrorMessage = "Unable to locate pulled chart artifact"
    )

    $chartFile = Get-ChildItem -Path $SearchDirectory -Filter "*.tgz" | Select-Object -First 1
    if (-not $chartFile) {
        throw "##[error]$ErrorMessage"
    }

    $chartPath = $chartFile.FullName
    if ([string]::IsNullOrWhiteSpace($chartPath)) {
        throw "##[error]$ErrorMessage"
    }

    return $chartPath
}
