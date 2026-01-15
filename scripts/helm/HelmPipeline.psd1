@{
    RootModule        = 'HelmPipeline.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f9ec4b9b-2d8b-46b7-9d41-57180e9bca35'
    Author            = 'UKHO'
    CompanyName       = 'UKHO'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
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

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
