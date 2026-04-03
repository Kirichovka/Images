param(
    [string]$BaseRef,
    [string]$HeadRef,
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

$errorBytes = $ErrorKilobytes * 1KB
$emptyTreeSha = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

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

function Get-OutgoingImageFiles {
    param(
        [string]$RepoRoot,
        [string]$DiffBaseRef,
        [string]$DiffHeadRef
    )

    $gitArgs = @("diff", "--name-only", "--diff-filter=ACMR", $DiffBaseRef, $DiffHeadRef, "--")
    $changedPaths = & git @gitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to determine changed files for validation."
    }

    foreach ($relativePath in $changedPaths) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $normalizedRelativePath = $relativePath.Replace("\", "/")
        if ($normalizedRelativePath -match '^(?:\.git|\.github|scripts|\.githooks)/') {
            continue
        }

        $fullPath = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            continue
        }

        $file = Get-Item -LiteralPath $fullPath
        if ($supportedExtensions -contains $file.Extension.ToLowerInvariant()) {
            $file
        }
    }
}

if ([string]::IsNullOrWhiteSpace($HeadRef)) {
    $HeadRef = "HEAD"
}

if ([string]::IsNullOrWhiteSpace($BaseRef)) {
    $upstreamRef = $null
    try {
        $upstreamRef = (git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null).Trim()
    }
    catch {
        $upstreamRef = $null
    }

    if ([string]::IsNullOrWhiteSpace($upstreamRef)) {
        $BaseRef = $emptyTreeSha
    }
    else {
        $BaseRef = $upstreamRef
    }
}

$images = Get-OutgoingImageFiles -RepoRoot $repoRoot -DiffBaseRef $BaseRef -DiffHeadRef $HeadRef |
    Sort-Object FullName -Unique

$errors = @()

foreach ($image in $images) {
    $relativePath = Get-RelativePath -BasePath $repoRoot -TargetPath $image.FullName
    $sizeText = "{0:N1} KB" -f ($image.Length / 1KB)

    if ($image.Length -gt $errorBytes) {
        $errors += "$($relativePath.Replace('\', '/')) - $sizeText exceeds ${ErrorKilobytes} KB"
        continue
    }

}

if ($images.Count -eq 0) {
    Write-Host "No changed images detected in this push."
    exit 0
}

Write-Host "Scanned $($images.Count) changed image(s). Push is blocked only for files above $ErrorKilobytes KB."

if ($errors.Count -gt 0) {
    Write-Error "Images above ${ErrorKilobytes} KB were found. Reduce their size before pushing."
    foreach ($error in $errors) {
        Write-Error " - $error"
    }
    exit 1
}

Write-Host "Image size validation passed."
