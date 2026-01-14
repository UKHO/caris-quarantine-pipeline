function Get-HelmChartVersionFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryName,

        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$FallbackTag
    )

    function Invoke-AzCli {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string[]]$Arguments
        )

        $output = & az @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $message = ($output | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($message)) {
                $message = "az exited with code $exitCode"
            }
            throw $message
        }

        return ($output | Out-String).Trim()
    }

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
            $ManifestObject
        )

        if ($null -eq $ManifestObject) {
            return $null
        }

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
        try {
            $tagToUse = Invoke-AzCli -Arguments @(
                'acr', 'repository', 'show-tags',
                '--name', $RegistryName,
                '--repository', $Repository,
                '--orderby', 'time_desc',
                '--top', '1',
                '--output', 'tsv',
                '--only-show-errors'
            )
        }
        catch {
            Write-Host "##[warning]Unable to query latest tag for $Repository in $RegistryName via 'az acr repository show-tags': $($_.Exception.Message)"
            $tagToUse = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($tagToUse)) {
        throw "Unable to determine Helm chart tag/version for $Repository in $RegistryName"
    }

    $manifest = $null
    try {
        $manifestJson = Invoke-AzCli -Arguments @(
            'acr', 'manifest', 'show',
            '--name', $RegistryName,
            '--repository', $Repository,
            '--tag', $tagToUse,
            '--output', 'json',
            '--only-show-errors'
        )

        if (-not [string]::IsNullOrWhiteSpace($manifestJson)) {
            try {
                $manifest = $manifestJson | ConvertFrom-Json
            }
            catch {
                Write-Host "##[warning]az acr manifest show returned non-JSON output for ${Repository}:$tagToUse in $RegistryName; falling back to tag."
                $manifest = $null
            }
        }
    }
    catch {
        Write-Host "##[warning]Unable to read manifest for ${Repository}:$tagToUse in $RegistryName via 'az acr manifest show'; falling back to tag. Error: $($_.Exception.Message)"
        $manifest = $null
    }

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
