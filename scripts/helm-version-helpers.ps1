function Get-HelmChartVersionFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryName,

        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$FallbackTag
    )

    function Get-ObjectPropertyValue {
        param(
            [Parameter(Mandatory)]
            $Object,

            [Parameter(Mandatory)]
            [string]$PropertyName
        )

        if ($null -eq $Object) {
            return $null
        }

        $prop = $Object.PSObject.Properties[$PropertyName]
        if ($null -eq $prop) {
            return $null
        }

        return $prop.Value
    }

    function Get-ChartVersionFromManifestObject {
        param(
            [Parameter(Mandatory)]
            $ManifestObject
        )

        $versionKey = 'org.opencontainers.image.version'

        $annotations = Get-ObjectPropertyValue -Object $ManifestObject -PropertyName 'annotations'
        $version = if ($null -ne $annotations) { $annotations.$versionKey } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            return $version
        }

        $config = Get-ObjectPropertyValue -Object $ManifestObject -PropertyName 'config'
        $configAnnotations = Get-ObjectPropertyValue -Object $config -PropertyName 'annotations'
        $version = if ($null -ne $configAnnotations) { $configAnnotations.$versionKey } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            return $version
        }

        $properties = Get-ObjectPropertyValue -Object $ManifestObject -PropertyName 'properties'
        $propertiesAnnotations = Get-ObjectPropertyValue -Object $properties -PropertyName 'annotations'
        $version = if ($null -ne $propertiesAnnotations) { $propertiesAnnotations.$versionKey } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            return $version
        }

        return $null
    }

    $tagToUse = $FallbackTag
    if ([string]::IsNullOrWhiteSpace($tagToUse)) {
        $tagToUse = az acr repository show-tags --name $RegistryName --repository $Repository --orderby time_desc --top 1 --output tsv --only-show-errors
    }

    if ([string]::IsNullOrWhiteSpace($tagToUse)) {
        throw "Unable to determine Helm chart tag/version for $Repository in $RegistryName"
    }

    $manifestJson = az acr manifest show --name $RegistryName --repository $Repository --tag $tagToUse --output json --only-show-errors
    $manifest = $manifestJson | ConvertFrom-Json
    $chartVersion = Get-ChartVersionFromManifestObject -ManifestObject $manifest

    if ([string]::IsNullOrWhiteSpace($chartVersion)) {
        Write-Host "##[warning]Could not determine chart version from manifest for $Repository in $RegistryName, using tag '$tagToUse'"
        $chartVersion = $tagToUse
    }

    if ([string]::IsNullOrWhiteSpace($chartVersion)) {
        throw "Unable to determine Helm chart version for $Repository in $RegistryName"
    }

    return $chartVersion
}
