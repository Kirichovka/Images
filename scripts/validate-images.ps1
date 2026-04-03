param(
    [int]$WarningKilobytes = 100,
    [int]$ErrorKilobytes = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path.TrimEnd('\', '/')

$supportedExtensions = @(
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".svg",
    ".avif"
)

$warningBytes = $WarningKilobytes * 1KB
$errorBytes = $ErrorKilobytes * 1KB

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $resolvedBasePath = (Resolve-Path $BasePath).Path.TrimEnd('\', '/')
    $resolvedTargetPath = (Resolve-Path $TargetPath).Path

    if (-not $resolvedTargetPath.StartsWith($resolvedBasePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$resolvedTargetPath' is not inside '$resolvedBasePath'."
    }

    return $resolvedTargetPath.Substring($resolvedBasePath.Length).TrimStart('\', '/')
}

$images = Get-ChildItem -Path $repoRoot -Recurse -File |
    Where-Object {
        $relativePath = Get-RelativePath -BasePath $repoRoot -TargetPath $_.FullName
        $normalizedRelativePath = $relativePath.Replace("\", "/")

        $supportedExtensions -contains $_.Extension.ToLowerInvariant() -and
        $normalizedRelativePath -notmatch '^(?:\.git|\.github|scripts|\.githooks)/'
    } |
    Sort-Object FullName

$warnings = @()
$errors = @()

foreach ($image in $images) {
    $relativePath = Get-RelativePath -BasePath $repoRoot -TargetPath $image.FullName
    $sizeText = "{0:N1} KB" -f ($image.Length / 1KB)

    if ($image.Length -gt $errorBytes) {
        $errors += "$($relativePath.Replace('\', '/')) - $sizeText exceeds ${ErrorKilobytes} KB"
        continue
    }

    if ($image.Length -gt $warningBytes) {
        $warnings += "$($relativePath.Replace('\', '/')) - $sizeText exceeds ${WarningKilobytes} KB"
    }
}

Write-Host "Scanned $($images.Count) image(s). Warning threshold: $WarningKilobytes KB. Error threshold: $ErrorKilobytes KB."

if ($warnings.Count -gt 0) {
    Write-Warning "Large images detected but allowed:"
    foreach ($warning in $warnings) {
        Write-Warning " - $warning"
    }
}

if ($errors.Count -gt 0) {
    Write-Error "Images above ${ErrorKilobytes} KB were found. Reduce their size before pushing."
    foreach ($error in $errors) {
        Write-Error " - $error"
    }
    exit 1
}

Write-Host "Image size validation passed."
