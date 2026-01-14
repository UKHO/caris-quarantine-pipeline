function Expand-HelmChartArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChartArchivePath,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path $ChartArchivePath)) {
        throw "Helm chart archive not found at $ChartArchivePath"
    }

    $extractDir = New-Item -ItemType Directory -Path $Destination -Force
    & tar -xzf $ChartArchivePath -C $extractDir.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract Helm chart archive $ChartArchivePath"
    }

    $chartDir = Get-ChildItem -Path $extractDir.FullName -Directory | Select-Object -First 1
    if (-not $chartDir) {
        throw "Unable to locate chart directory after extracting $ChartArchivePath"
    }

    return $chartDir.FullName
}

function Get-HelmChartVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChartDirectory
    )

    $chartYamlPath = Join-Path $ChartDirectory 'Chart.yaml'
    if (-not (Test-Path $chartYamlPath)) {
        throw "Chart.yaml not found in $ChartDirectory"
    }

    $chartYaml = Get-Content -Path $chartYamlPath -Raw
    $versionMatch = [regex]::Match($chartYaml, 'version:\s*(.+)')
    if (-not $versionMatch.Success) {
        throw "Unable to detect chart version inside $chartYamlPath"
    }

    return $versionMatch.Groups[1].Value.Trim()
}

function Set-HelmChartVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChartDirectory,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $chartYamlPath = Join-Path $ChartDirectory 'Chart.yaml'
    if (-not (Test-Path $chartYamlPath)) {
        throw "Chart.yaml not found in $ChartDirectory"
    }

    $chartYaml = Get-Content -Path $chartYamlPath -Raw
    if ($chartYaml -notmatch 'version:\s+.*') {
        throw "Chart.yaml in $ChartDirectory does not contain a version field"
    }

    $updatedChartYaml = $chartYaml -replace 'version:\s+.*', "version: $Version"
    Set-Content -Path $chartYamlPath -Value $updatedChartYaml
}
