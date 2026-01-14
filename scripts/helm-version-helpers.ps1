function Get-HelmChartVersionFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryName,

        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$FallbackTag
    )

    $manifest = az acr manifest show --name $Repository --registry $RegistryName --output json | ConvertFrom-Json
    $chartVersion = $manifest.config.annotations.'org.opencontainers.image.version'

    if ([string]::IsNullOrWhiteSpace($chartVersion) -and $FallbackTag) {
        Write-Host "##[warning]Could not determine chart version from manifest for $Repository in $RegistryName, using fallback tag $FallbackTag"
        $chartVersion = $FallbackTag
    }

    if ([string]::IsNullOrWhiteSpace($chartVersion)) {
        throw "Unable to determine Helm chart version for $Repository in $RegistryName"
    }

    return $chartVersion
}
