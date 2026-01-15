Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

function Get-AcrRegistryNameFromHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryHost
    )

    $hostValue = $RegistryHost.Trim()
    if ([string]::IsNullOrWhiteSpace($hostValue)) {
        throw 'RegistryHost cannot be empty'
    }

    return ($hostValue -split '\.')[0]
}

function New-PipelineTempDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $root = $env:AGENT_TEMPDIRECTORY
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = [System.IO.Path]::GetTempPath()
    }

    $path = Join-Path $root $Name
    $dir = New-Item -ItemType Directory -Path $path -Force
    Write-Host "Using temp directory: $($dir.FullName)"
    return $dir
}

function Get-AcrAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryName,

        [string]$RegistryHost
    )

    $accessToken = az acr login --name $RegistryName --expose-token --output tsv --query accessToken
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        $target = if ([string]::IsNullOrWhiteSpace($RegistryHost)) { $RegistryName } else { $RegistryHost }
        throw "Failed to obtain registry token for $target"
    }

    return $accessToken
}

function Invoke-HelmRegistryCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryHost,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [string[]]$HelmArguments
    )

    try {
        $AccessToken | helm registry login $RegistryHost --username 00000000-0000-0000-0000-000000000000 --password-stdin
        helm @HelmArguments
    }
    finally {
        helm registry logout $RegistryHost | Out-Null
    }
}

function Invoke-HelmRegistryPull {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryHost,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [string]$ChartReference,

        [string]$Destination,

        [string]$Version,

        [switch]$Untar
    )

    $args = @('pull', $ChartReference)
    if ($PSBoundParameters.ContainsKey('Version') -and $Version) {
        $args += @('--version', $Version)
    }
    if ($PSBoundParameters.ContainsKey('Destination') -and $Destination) {
        $args += @('--destination', $Destination)
    }
    if ($Untar.IsPresent) {
        $args += '--untar'
    }

    Invoke-HelmRegistryCommand -RegistryHost $RegistryHost -AccessToken $AccessToken -HelmArguments $args
}

function Invoke-HelmRegistryPush {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryHost,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [string]$ChartPath,

        [Parameter(Mandatory)]
        [string]$ChartReference
    )

    $args = @('push', $ChartPath, $ChartReference)
    Invoke-HelmRegistryCommand -RegistryHost $RegistryHost -AccessToken $AccessToken -HelmArguments $args
}

function Invoke-HelmPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChartDirectory,

        [Parameter(Mandatory)]
        [string]$Version,

        [string]$Destination
    )

    $cmd = @('package', $ChartDirectory)
    if ($PSBoundParameters.ContainsKey('Destination') -and $Destination) {
        $cmd += @('--destination', $Destination)
    }

    $packageOutput = helm @cmd
    Write-Host $packageOutput

    if ($packageOutput -match ':\s+(.+\.tgz)$') {
        return $matches[1]
    }

    $chartName = Split-Path $ChartDirectory -Leaf
    $artifactPattern = if ($chartName) { "$chartName-$Version.tgz" } else { "*-$Version.tgz" }
    return (Get-ChildItem -Path ($Destination ?? (Split-Path $ChartDirectory -Parent)) -Filter $artifactPattern | Select-Object -First 1).FullName
}

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

Export-ModuleMember -Function @(
    'Get-AcrRegistryNameFromHost',
    'New-PipelineTempDirectory',
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
