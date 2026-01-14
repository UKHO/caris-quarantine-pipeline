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
