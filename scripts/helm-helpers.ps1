# Helper functions for Helm registry interactions within the quarantine pipelines.

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
