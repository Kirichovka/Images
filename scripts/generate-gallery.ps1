Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$resolvedRepoRoot = (Resolve-Path $repoRoot).Path.TrimEnd('\', '/')
$outputPath = Join-Path $resolvedRepoRoot "index.html"

$supportedExtensions = @(
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".svg",
    ".avif"
)

function Get-RelativeWebPath {
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

function Convert-ToUrlPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $segments = $RelativePath -split "[/\\]" | Where-Object { $_ -ne "" }
    return ($segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join "/"
}

function Convert-ToHtmlText {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function Get-SizeState {
    param(
        [Parameter(Mandatory = $true)]
        [long]$Length
    )

    if ($Length -gt 200KB) {
        return "error"
    }

    if ($Length -gt 100KB) {
        return "warning"
    }

    return "ok"
}

function Get-GitHubRepositoryInfo {
    $remoteUrl = (git config --get remote.origin.url 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
        return @{
            owner = ""
            repo = ""
        }
    }

    $match = [regex]::Match($remoteUrl.Trim(), 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+?)(?:\.git)?$')
    if (-not $match.Success) {
        return @{
            owner = ""
            repo = ""
        }
    }

    return @{
        owner = $match.Groups["owner"].Value
        repo = $match.Groups["repo"].Value
    }
}

$trackedPaths = @(git ls-files --)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read tracked files from git."
}

$images = @(foreach ($trackedPath in $trackedPaths) {
    if ([string]::IsNullOrWhiteSpace($trackedPath)) {
        continue
    }

    $normalizedRelativePath = $trackedPath.Replace("\", "/")
    if ($normalizedRelativePath -match '^(?:\.git|\.github|scripts)/') {
        continue
    }

    $fullPath = Join-Path $resolvedRepoRoot $trackedPath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }

    $file = Get-Item -LiteralPath $fullPath
    if ($supportedExtensions -contains $file.Extension.ToLowerInvariant()) {
        $file
    }
}) | Sort-Object FullName

$imageCatalog = foreach ($image in $images) {
    $relativePath = (Get-RelativeWebPath -BasePath $resolvedRepoRoot -TargetPath $image.FullName).Replace("\", "/")
    $urlPath = Convert-ToUrlPath -RelativePath $relativePath
    $sizeLabel = "{0:N1} KB" -f ($image.Length / 1KB)
    $sizeState = Get-SizeState -Length $image.Length

    [PSCustomObject]@{
        name = $image.Name
        path = $relativePath
        urlPath = $urlPath
        publicUrl = "./$urlPath"
        sizeBytes = [int64]$image.Length
        sizeLabel = $sizeLabel
        modifiedLabel = $image.LastWriteTime.ToString("yyyy-MM-dd")
        modifiedIso = $image.LastWriteTime.ToString("o")
        state = $sizeState
    }
}

$galleryItems = foreach ($catalogImage in $imageCatalog) {
    $displayPath = Convert-ToHtmlText($catalogImage.path)
    $displayName = Convert-ToHtmlText($catalogImage.name)
    $displaySize = Convert-ToHtmlText($catalogImage.sizeLabel)
    $displayPublicUrl = Convert-ToHtmlText($catalogImage.publicUrl)
    $displayManagePath = Convert-ToHtmlText($catalogImage.path)
    $cardClass = "card"
    $noticeMarkup = ""

    if ($catalogImage.state -eq "warning") {
        $cardClass = "card card-warning"
        $noticeMarkup = '<p class="size-notice" aria-label="Large file warning">Warning: file is larger than 100 KB and may slow down your site.</p>'
    }
    elseif ($catalogImage.state -eq "error") {
        $cardClass = "card card-error"
        $noticeMarkup = '<p class="size-notice" aria-label="File too large">Error: file is larger than 200 KB and should be optimized before publishing.</p>'
    }

@"
        <article class="$cardClass">
          <a class="preview" href="$displayPublicUrl" target="_blank" rel="noreferrer">
            <img src="$displayPublicUrl" alt="$displayName" loading="lazy">
          </a>
          <div class="meta">
            <h2>$displayName</h2>
            <p class="path">$displayPath</p>
            <p class="size">$displaySize</p>
            $noticeMarkup
            <div class="card-actions">
              <a class="direct-link" href="$displayPublicUrl" target="_blank" rel="noreferrer">Open direct link</a>
              <button class="manage-link" type="button" data-open-manager="delete" data-image-path="$displayManagePath">Manage file</button>
            </div>
          </div>
        </article>
"@
}

$imageCount = $images.Count
$lastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$githubRepoInfo = Get-GitHubRepositoryInfo
$galleryConfigJson = @{
    owner = $githubRepoInfo.owner
    repo = $githubRepoInfo.repo
    branch = "main"
    warningBytes = 102400
    errorBytes = 204800
    defaultFolder = "uploads"
    existingImages = $imageCatalog
} | ConvertTo-Json -Compress

if ($galleryItems.Count -eq 0) {
    $galleryMarkup = @"
      <div class="empty-state">
        <p>No supported images were found in this repository yet.</p>
      </div>
"@
}
else {
    $galleryMarkup = ($galleryItems -join [Environment]::NewLine)
}

$html = @"
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Images Library</title>
    <meta name="description" content="Static image library published with GitHub Pages.">
    <style>
      :root {
        --bg: #f3efe6;
        --surface: rgba(255, 252, 247, 0.88);
        --surface-strong: #fffdf8;
        --text: #1f1a17;
        --muted: #6a5d53;
        --accent: #d95d39;
        --accent-strong: #b9441f;
        --border: rgba(52, 36, 24, 0.12);
        --shadow: 0 20px 45px rgba(71, 51, 39, 0.12);
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        font-family: Georgia, "Times New Roman", serif;
        color: var(--text);
        background:
          radial-gradient(circle at top left, rgba(217, 93, 57, 0.18), transparent 35%),
          linear-gradient(160deg, #f6f0e3 0%, #efe7da 55%, #e6dfd4 100%);
        min-height: 100vh;
      }

      .shell {
        width: min(1200px, calc(100% - 32px));
        margin: 0 auto;
        padding: 48px 0 64px;
      }

      .hero {
        background: linear-gradient(135deg, rgba(255, 250, 241, 0.94), rgba(255, 245, 230, 0.84));
        border: 1px solid var(--border);
        border-radius: 28px;
        box-shadow: var(--shadow);
        overflow: hidden;
        position: relative;
      }

      .hero::after {
        content: "";
        position: absolute;
        inset: auto -60px -60px auto;
        width: 220px;
        height: 220px;
        border-radius: 50%;
        background: radial-gradient(circle, rgba(217, 93, 57, 0.22), transparent 68%);
      }

      .hero-inner {
        padding: 34px 28px;
        position: relative;
        z-index: 1;
      }

      .eyebrow {
        margin: 0 0 10px;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        font-size: 12px;
        color: var(--accent-strong);
      }

      h1 {
        margin: 0;
        font-size: clamp(34px, 5vw, 60px);
        line-height: 0.98;
      }

      .lead {
        max-width: 760px;
        margin: 18px 0 0;
        font-size: 18px;
        line-height: 1.6;
        color: var(--muted);
      }

      .stats {
        display: flex;
        gap: 14px;
        flex-wrap: wrap;
        margin-top: 24px;
      }

      .stat {
        background: rgba(255, 255, 255, 0.7);
        border: 1px solid rgba(52, 36, 24, 0.08);
        border-radius: 999px;
        padding: 10px 16px;
        font-size: 14px;
      }

      .hero-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 24px;
      }

      .secondary-button,
      .ghost-button {
        appearance: none;
        border: 0;
        cursor: pointer;
        font: inherit;
        text-decoration: none;
        border-radius: 999px;
        padding: 12px 18px;
      }

      .secondary-button {
        color: white;
        background: linear-gradient(135deg, var(--accent), var(--accent-strong));
        box-shadow: 0 14px 28px rgba(217, 93, 57, 0.22);
      }

      .ghost-button {
        color: var(--text);
        background: rgba(255, 255, 255, 0.72);
        border: 1px solid rgba(52, 36, 24, 0.12);
      }

      .uploader-panel {
        margin-top: 28px;
        background: linear-gradient(135deg, rgba(255, 250, 241, 0.94), rgba(250, 244, 233, 0.84));
        border: 1px solid var(--border);
        border-radius: 28px;
        box-shadow: var(--shadow);
        padding: 24px;
      }

      .uploader-panel h2 {
        margin: 0 0 10px;
        font-size: 30px;
      }

      .uploader-panel p {
        margin: 0;
        color: var(--muted);
        line-height: 1.6;
      }

      .uploader-points {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 12px;
        margin-top: 18px;
      }

      .uploader-point {
        border-radius: 20px;
        padding: 16px;
        background: rgba(255, 255, 255, 0.72);
        border: 1px solid rgba(52, 36, 24, 0.1);
      }

      .uploader-point strong {
        display: block;
        margin-bottom: 6px;
      }

      .gallery {
        margin-top: 28px;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        gap: 18px;
      }

      .card {
        display: flex;
        flex-direction: column;
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 24px;
        overflow: hidden;
        box-shadow: var(--shadow);
        backdrop-filter: blur(10px);
        transform: translateY(0);
        transition: transform 180ms ease, box-shadow 180ms ease;
      }

      .card-warning {
        border-color: rgba(184, 134, 11, 0.45);
        box-shadow: 0 24px 48px rgba(184, 134, 11, 0.18);
        background:
          linear-gradient(180deg, rgba(255, 248, 214, 0.95), rgba(255, 252, 247, 0.88));
      }

      .card-warning .preview {
        outline: 4px solid rgba(214, 168, 0, 0.26);
        outline-offset: -4px;
      }

      .card-warning .meta h2::after {
        content: "Large file";
        display: inline-block;
        margin-left: 10px;
        padding: 5px 9px;
        border-radius: 999px;
        font-size: 11px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #725300;
        background: rgba(244, 202, 68, 0.32);
        border: 1px solid rgba(184, 134, 11, 0.25);
        vertical-align: middle;
      }

      .card-error {
        border-color: rgba(175, 57, 36, 0.4);
        box-shadow: 0 24px 48px rgba(175, 57, 36, 0.2);
        background:
          linear-gradient(180deg, rgba(255, 233, 228, 0.96), rgba(255, 252, 247, 0.88));
      }

      .card-error .preview {
        outline: 4px solid rgba(217, 93, 57, 0.28);
        outline-offset: -4px;
      }

      .card-error .meta h2::after {
        content: "Too large";
        display: inline-block;
        margin-left: 10px;
        padding: 5px 9px;
        border-radius: 999px;
        font-size: 11px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #8a2d16;
        background: rgba(217, 93, 57, 0.16);
        border: 1px solid rgba(175, 57, 36, 0.24);
        vertical-align: middle;
      }

      .card:hover {
        transform: translateY(-4px);
        box-shadow: 0 24px 50px rgba(71, 51, 39, 0.18);
      }

      .preview {
        display: block;
        background:
          linear-gradient(45deg, rgba(217, 93, 57, 0.08) 25%, transparent 25%, transparent 75%, rgba(217, 93, 57, 0.08) 75%),
          linear-gradient(45deg, rgba(217, 93, 57, 0.08) 25%, transparent 25%, transparent 75%, rgba(217, 93, 57, 0.08) 75%);
        background-position: 0 0, 14px 14px;
        background-size: 28px 28px;
        aspect-ratio: 4 / 3;
        overflow: hidden;
      }

      .preview img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
      }

      .meta {
        display: grid;
        gap: 10px;
        padding: 18px;
      }

      .meta h2 {
        margin: 0;
        font-size: 21px;
        line-height: 1.15;
      }

      .path,
      .size {
        margin: 0;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.5;
        word-break: break-word;
      }

      .size-notice {
        margin: 0;
        padding: 10px 12px;
        border-radius: 14px;
        font-size: 14px;
        line-height: 1.45;
        border: 1px solid rgba(184, 134, 11, 0.25);
        background: rgba(244, 202, 68, 0.18);
        color: #6e5100;
      }

      .card-error .size-notice {
        border-color: rgba(175, 57, 36, 0.22);
        background: rgba(217, 93, 57, 0.12);
        color: #8a2d16;
      }

      .card-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-top: 2px;
      }

      .direct-link,
      .manage-link {
        width: fit-content;
        text-decoration: none;
        padding: 10px 14px;
        border-radius: 999px;
        font-size: 14px;
        font: inherit;
        cursor: pointer;
      }

      .direct-link {
        color: white;
        background: linear-gradient(135deg, var(--accent), var(--accent-strong));
      }

      .manage-link {
        color: var(--text);
        background: rgba(255, 255, 255, 0.82);
        border: 1px solid rgba(52, 36, 24, 0.14);
      }

      .empty-state {
        margin-top: 28px;
        background: var(--surface-strong);
        border-radius: 24px;
        border: 1px solid var(--border);
        padding: 24px;
        box-shadow: var(--shadow);
      }

      footer {
        margin-top: 18px;
        color: var(--muted);
        font-size: 13px;
      }

      .manager-shell {
        position: fixed;
        inset: 0;
        display: none;
        align-items: center;
        justify-content: center;
        padding: 18px;
        background: rgba(24, 18, 13, 0.58);
        backdrop-filter: blur(8px);
        z-index: 20;
      }

      .manager-shell.is-open {
        display: flex;
      }

      .manager-card {
        width: min(1240px, 100%);
        max-height: min(92vh, 1040px);
        overflow: auto;
        background: linear-gradient(180deg, rgba(255, 253, 248, 0.98), rgba(246, 239, 228, 0.96));
        border-radius: 34px;
        border: 6px solid #17110d;
        box-shadow: 0 38px 100px rgba(18, 12, 8, 0.34);
      }

      .modal-head {
        display: flex;
        justify-content: space-between;
        gap: 20px;
        align-items: flex-start;
        padding: 28px 28px 0;
      }

      .modal-head h3 {
        margin: 0;
        font-size: clamp(30px, 4vw, 46px);
        line-height: 0.95;
      }

      .modal-head p {
        margin: 10px 0 0;
        color: var(--muted);
        line-height: 1.6;
        max-width: 720px;
      }

      .mode-tabs {
        display: inline-flex;
        gap: 10px;
        margin-top: 18px;
        padding: 8px;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.72);
        border: 2px solid rgba(23, 17, 13, 0.12);
      }

      .mode-tab {
        appearance: none;
        border: 2px solid transparent;
        background: transparent;
        color: var(--muted);
        cursor: pointer;
        border-radius: 999px;
        padding: 10px 16px;
        font: inherit;
      }

      .mode-tab.is-active {
        border-color: #17110d;
        background: #17110d;
        color: #fff8f0;
      }

      .manager-layout {
        display: grid;
        grid-template-columns: minmax(0, 1.08fr) minmax(340px, 0.92fr);
        gap: 22px;
        padding: 24px 28px 28px;
      }

      .preview-panel,
      .control-panel {
        border-radius: 28px;
        border: 4px solid #17110d;
        background: rgba(255, 255, 255, 0.76);
      }

      .preview-panel {
        padding: 18px;
        display: grid;
        gap: 18px;
      }

      .preview-frame {
        position: relative;
        min-height: 520px;
        border-radius: 24px;
        border: 4px solid #17110d;
        background:
          linear-gradient(135deg, rgba(255, 252, 246, 0.98), rgba(249, 241, 226, 0.98));
        overflow: hidden;
      }

      .preview-window {
        width: 100%;
        height: 100%;
        min-height: 520px;
        display: grid;
        place-items: center;
        padding: 28px;
      }

      .preview-asset {
        max-width: 100%;
        max-height: 420px;
        display: block;
        object-fit: contain;
        filter: drop-shadow(0 18px 35px rgba(28, 20, 15, 0.12));
      }

      .preview-placeholder {
        text-align: center;
        display: grid;
        gap: 12px;
        color: var(--muted);
      }

      .preview-placeholder strong {
        font-size: clamp(28px, 5vw, 48px);
        color: var(--text);
      }

      .preview-arrow {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        width: 62px;
        height: 62px;
        border-radius: 50%;
        border: 4px solid #17110d;
        background: rgba(255, 255, 255, 0.96);
        color: #17110d;
        font-size: 28px;
        line-height: 1;
        cursor: pointer;
      }

      .preview-arrow[disabled] {
        opacity: 0.35;
        cursor: not-allowed;
      }

      .preview-arrow.prev {
        left: 18px;
      }

      .preview-arrow.next {
        right: 18px;
      }

      .preview-badge {
        position: absolute;
        top: 18px;
        right: 18px;
        padding: 10px 14px;
        border-radius: 999px;
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        border: 2px solid #17110d;
        background: rgba(255, 255, 255, 0.94);
      }

      .preview-badge.warning {
        background: rgba(244, 202, 68, 0.3);
        color: #725300;
      }

      .preview-badge.error {
        background: rgba(217, 93, 57, 0.18);
        color: #8a2d16;
      }

      .preview-meta {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
        gap: 12px;
      }

      .meta-pair {
        padding: 14px 16px;
        border-radius: 18px;
        border: 2px solid rgba(23, 17, 13, 0.12);
        background: rgba(255, 255, 255, 0.82);
      }

      .meta-pair span {
        display: block;
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted);
        margin-bottom: 8px;
      }

      .meta-pair strong {
        display: block;
        font-size: 18px;
        line-height: 1.25;
        word-break: break-word;
      }

      .thumb-strip {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
        gap: 12px;
      }

      .thumb-card {
        position: relative;
        padding: 10px;
        border-radius: 22px;
        border: 3px solid rgba(23, 17, 13, 0.16);
        background: rgba(255, 255, 255, 0.82);
        cursor: pointer;
        text-align: left;
      }

      .thumb-card.is-active {
        border-color: #17110d;
        transform: translateY(-2px);
        box-shadow: 0 16px 30px rgba(28, 20, 15, 0.12);
      }

      .thumb-card.warning {
        background: rgba(255, 247, 214, 0.92);
      }

      .thumb-card.error {
        background: rgba(255, 233, 228, 0.94);
      }

      .thumb-card img {
        width: 100%;
        aspect-ratio: 1 / 1;
        object-fit: cover;
        display: block;
        border-radius: 16px;
        border: 2px solid rgba(23, 17, 13, 0.12);
        background: rgba(255, 250, 241, 0.9);
      }

      .thumb-label {
        display: block;
        margin-top: 10px;
        font-size: 14px;
        line-height: 1.3;
        word-break: break-word;
      }

      .thumb-sub {
        display: block;
        margin-top: 4px;
        font-size: 12px;
        color: var(--muted);
      }

      .thumb-remove {
        position: absolute;
        top: 16px;
        right: 16px;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 2px solid #17110d;
        background: rgba(255, 255, 255, 0.98);
        color: #17110d;
        cursor: pointer;
      }

      .strip-empty {
        padding: 18px;
        border-radius: 20px;
        border: 2px dashed rgba(23, 17, 13, 0.16);
        color: var(--muted);
        text-align: center;
      }

      .control-panel {
        padding: 18px;
      }

      .control-stack {
        display: grid;
        gap: 16px;
      }

      .control-title {
        display: grid;
        gap: 8px;
      }

      .control-title h4 {
        margin: 0;
        font-size: 28px;
      }

      .control-title p {
        margin: 0;
        color: var(--muted);
        line-height: 1.6;
      }

      .field {
        display: grid;
        gap: 8px;
      }

      .field label {
        font-size: 14px;
        color: var(--muted);
      }

      .field input {
        width: 100%;
        padding: 16px 18px;
        border-radius: 18px;
        border: 4px solid #17110d;
        background: rgba(255, 255, 255, 0.96);
        color: var(--text);
        font: inherit;
      }

      .field input[readonly] {
        background: rgba(242, 238, 231, 0.9);
        color: #4e433a;
      }

      .mode-note,
      .manager-feedback,
      .selection-summary {
        margin: 0;
        padding: 14px 16px;
        border-radius: 18px;
        border: 2px solid rgba(23, 17, 13, 0.12);
        background: rgba(255, 255, 255, 0.84);
        line-height: 1.55;
      }

      .manager-feedback {
        display: none;
      }

      .manager-feedback.is-visible {
        display: block;
      }

      .manager-feedback.info {
        background: rgba(255, 245, 230, 0.94);
      }

      .manager-feedback.success {
        background: rgba(231, 247, 236, 0.96);
        color: #245736;
      }

      .manager-feedback.error {
        background: rgba(255, 233, 228, 0.98);
        color: #8a2d16;
      }

      .dropzone {
        border-radius: 24px;
        border: 4px dashed #17110d;
        background:
          linear-gradient(135deg, rgba(255, 246, 237, 0.96), rgba(255, 252, 247, 0.98));
        padding: 28px;
        text-align: center;
        display: grid;
        gap: 12px;
      }

      .dropzone.is-active {
        background:
          linear-gradient(135deg, rgba(255, 239, 227, 0.98), rgba(255, 251, 243, 0.98));
      }

      .dropzone strong {
        font-size: 26px;
      }

      .dropzone p {
        margin: 0;
        color: var(--muted);
      }

      .dropzone-actions,
      .action-group {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
      }

      .secondary-button,
      .ghost-button,
      .danger-button {
        appearance: none;
        border-radius: 999px;
        padding: 12px 18px;
        font: inherit;
        text-decoration: none;
        cursor: pointer;
      }

      .secondary-button {
        border: 3px solid #17110d;
        color: #fff9f1;
        background: #17110d;
      }

      .ghost-button {
        border: 3px solid #17110d;
        color: #17110d;
        background: rgba(255, 255, 255, 0.92);
      }

      .danger-button {
        border: 3px solid #7d2818;
        color: #fff7f4;
        background: #a33c25;
      }

      .secondary-button[disabled],
      .ghost-button[disabled],
      .danger-button[disabled],
      .thumb-remove[disabled],
      .mode-tab[disabled] {
        opacity: 0.45;
        cursor: not-allowed;
      }

      .control-actions {
        display: grid;
        gap: 14px;
        padding-top: 8px;
      }

      .status-note {
        color: var(--muted);
        font-size: 14px;
      }

      @media (max-width: 640px) {
        .shell {
          width: min(100% - 20px, 1200px);
          padding: 20px 0 40px;
        }

        .hero-inner {
          padding: 24px 20px;
        }

        .modal-head {
          padding-left: 18px;
          padding-right: 18px;
        }

        .manager-layout {
          grid-template-columns: 1fr;
          padding: 18px;
        }

        .preview-frame,
        .preview-window {
          min-height: 360px;
        }

        .preview-meta,
        .thumb-strip {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </head>
  <body>
    <main class="shell">
      <section class="hero">
        <div class="hero-inner">
          <p class="eyebrow">GitHub Pages Image Library</p>
          <h1>Images ready for the web.</h1>
          <p class="lead">
            Every file in this repository is published as a static asset. Open any preview to get a direct public URL you can use on your website, or upload new images from this page in a separate image-only commit.
          </p>
          <div class="stats">
            <div class="stat">$imageCount image(s)</div>
            <div class="stat">Updated $lastUpdated</div>
          </div>
          <div class="hero-actions">
            <button class="secondary-button" type="button" id="open-uploader">Open media manager</button>
            <a class="ghost-button" href="https://github.com/$($githubRepoInfo.owner)/$($githubRepoInfo.repo)/actions" target="_blank" rel="noreferrer">View deploy status</a>
          </div>
        </div>
      </section>

      <section class="uploader-panel">
        <h2>Manage images separately from code pushes.</h2>
        <p>
          The media manager creates dedicated image commits for uploads and deletions, so asset maintenance stays separate from your local code workflow.
        </p>
        <div class="uploader-points">
          <div class="uploader-point">
            <strong>Browser upload</strong>
            Images are committed directly to the repository through GitHub API.
          </div>
          <div class="uploader-point">
            <strong>Safe token handling</strong>
            Your GitHub token is used only in this tab and is never stored by this page.
          </div>
          <div class="uploader-point">
            <strong>Same size rules</strong>
            Files above 100 KB are marked as large, and files above 200 KB are blocked before upload.
          </div>
        </div>
      </section>

      <section class="gallery">
$galleryMarkup
      </section>

      <footer>
        Repository root files are available at <code>/filename.ext</code>, nested files at <code>/folder/filename.ext</code>.
      </footer>
    </main>
    <div class="manager-shell" id="uploader-modal" aria-hidden="true">
      <div class="manager-card" role="dialog" aria-modal="true" aria-labelledby="uploader-title">
        <div class="modal-head">
          <div>
            <p class="eyebrow">Media Manager</p>
            <h3 id="uploader-title">Upload or remove images in one place</h3>
            <p>
              Use a fine-grained GitHub token with repository contents write access. Uploads and deletions create separate image-focused commits, so they stay independent from your local code pushes.
            </p>
            <div class="mode-tabs">
              <button class="mode-tab is-active" type="button" data-mode-tab="upload">Upload</button>
              <button class="mode-tab" type="button" data-mode-tab="delete">Delete</button>
            </div>
          </div>
          <button class="ghost-button" type="button" id="close-uploader">Close</button>
        </div>
        <div class="manager-layout">
          <section class="preview-panel">
            <div class="preview-frame">
              <button class="preview-arrow prev" type="button" id="preview-prev" aria-label="Previous image">&larr;</button>
              <div class="preview-window" id="preview-window"></div>
              <button class="preview-arrow next" type="button" id="preview-next" aria-label="Next image">&rarr;</button>
            </div>
            <div class="preview-meta" id="preview-meta"></div>
            <div class="thumb-strip" id="thumb-strip"></div>
          </section>

          <section class="control-panel">
            <div class="control-stack">
              <div class="control-title">
                <h4 id="control-title">Upload images</h4>
                <p id="control-hint">Select new files, review them on the left, then commit them straight into the repository.</p>
              </div>

              <div class="field">
                <label for="github-token">GitHub token</label>
                <input id="github-token" type="password" autocomplete="off" placeholder="github_pat_..." spellcheck="false">
              </div>

              <div class="field">
                <label for="commit-message">Commit message</label>
                <input id="commit-message" type="text" value="Upload images via media manager" placeholder="Upload images via media manager">
              </div>

              <div class="field">
                <label for="target-folder" id="target-label">Destination folder</label>
                <input id="target-folder" type="text" value="uploads" placeholder="uploads or movies">
              </div>

              <p class="mode-note" id="mode-note">
                Files larger than 100 KB stay allowed and are marked as large. Files larger than 200 KB are blocked before upload.
              </p>

              <div id="upload-controls">
                <div class="dropzone" id="dropzone">
                  <strong>Drop image files into the stage</strong>
                  <p>or pick them from your computer</p>
                  <input id="file-input" type="file" multiple accept=".png,.jpg,.jpeg,.gif,.webp,.svg,.avif,image/png,image/jpeg,image/gif,image/webp,image/svg+xml,image/avif" hidden>
                </div>
                <div class="dropzone-actions">
                  <button class="ghost-button" type="button" id="pick-files">Choose files</button>
                  <button class="ghost-button" type="button" id="clear-files">Clear selection</button>
                </div>
                <p class="selection-summary" id="selection-summary">No files selected yet.</p>
              </div>

              <div id="delete-controls" hidden>
                <p class="selection-summary" id="delete-summary">Choose an existing image on the left, then remove it with its own delete commit.</p>
                <div class="dropzone-actions">
                  <a class="ghost-button" id="open-current-image" href="#" target="_blank" rel="noreferrer">Open current image</a>
                  <button class="danger-button" type="button" id="delete-current">Delete current image</button>
                </div>
              </div>

              <p class="manager-feedback" id="upload-feedback" role="status" aria-live="polite"></p>

              <div class="control-actions">
                <div class="status-note" id="status-note">Choose files to start an upload, or switch to delete mode to remove an existing image.</div>
                <div class="action-group">
                  <button class="secondary-button" type="button" id="start-upload">Upload images</button>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
    <script>
      window.galleryConfig = $galleryConfigJson;

      (function () {
        const config = window.galleryConfig;
        const state = {
          mode: 'upload',
          files: [],
          existingImages: Array.isArray(config.existingImages) ? config.existingImages.slice() : [],
          currentUploadIndex: 0,
          currentDeleteIndex: 0,
          busy: false
        };

        const modal = document.getElementById('uploader-modal');
        const openButton = document.getElementById('open-uploader');
        const closeButton = document.getElementById('close-uploader');
        const previewWindow = document.getElementById('preview-window');
        const previewMeta = document.getElementById('preview-meta');
        const thumbStrip = document.getElementById('thumb-strip');
        const prevButton = document.getElementById('preview-prev');
        const nextButton = document.getElementById('preview-next');
        const modeTabs = Array.from(document.querySelectorAll('[data-mode-tab]'));
        const controlTitle = document.getElementById('control-title');
        const controlHint = document.getElementById('control-hint');
        const targetLabel = document.getElementById('target-label');
        const pickFilesButton = document.getElementById('pick-files');
        const fileInput = document.getElementById('file-input');
        const dropzone = document.getElementById('dropzone');
        const clearFilesButton = document.getElementById('clear-files');
        const deleteCurrentButton = document.getElementById('delete-current');
        const openCurrentImageLink = document.getElementById('open-current-image');
        const uploadButton = document.getElementById('start-upload');
        const feedback = document.getElementById('upload-feedback');
        const selectionSummary = document.getElementById('selection-summary');
        const deleteSummary = document.getElementById('delete-summary');
        const statusNote = document.getElementById('status-note');
        const tokenInput = document.getElementById('github-token');
        const folderInput = document.getElementById('target-folder');
        const commitMessageInput = document.getElementById('commit-message');
        const modeNote = document.getElementById('mode-note');
        const uploadControls = document.getElementById('upload-controls');
        const deleteControls = document.getElementById('delete-controls');

        function escapeHtml(value) {
          return String(value || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
        }

        function formatKilobytes(size) {
          return (size / 1024).toFixed(1) + ' KB';
        }

        function formatDate(value) {
          const date = new Date(value);
          if (Number.isNaN(date.getTime())) {
            return 'Unknown date';
          }

          return date.toLocaleDateString(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
          });
        }

        function encodePathSegments(path) {
          return String(path || '')
            .split('/')
            .filter(Boolean)
            .map(function (segment) {
              return encodeURIComponent(segment);
            })
            .join('/');
        }

        function getSizeState(size) {
          if (size > config.errorBytes) {
            return 'error';
          }

          if (size > config.warningBytes) {
            return 'warning';
          }

          return 'ok';
        }

        function getStateLabel(sizeState) {
          if (sizeState === 'error') {
            return 'Too large';
          }

          if (sizeState === 'warning') {
            return 'Large file';
          }

          return 'Ready';
        }

        function sanitizeFolder(value) {
          return String(value || '')
            .replace(/\\/g, '/')
            .replace(/^\/+|\/+$/g, '')
            .replace(/\/{2,}/g, '/')
            .trim();
        }

        function getSuggestedCommitMessage() {
          return state.mode === 'upload' ? 'Upload images via media manager' : 'Delete image via media manager';
        }

        function syncSuggestedCommitMessage(force) {
          const previousSuggested = commitMessageInput.dataset.suggestedValue || '';
          const nextSuggested = getSuggestedCommitMessage();
          const currentValue = commitMessageInput.value.trim();

          if (force || currentValue === '' || currentValue === previousSuggested) {
            commitMessageInput.value = nextSuggested;
          }

          commitMessageInput.dataset.suggestedValue = nextSuggested;
        }

        function setFeedback(kind, message) {
          feedback.textContent = message;
          feedback.className = 'manager-feedback is-visible ' + kind;
        }

        function clearFeedback() {
          feedback.textContent = '';
          feedback.className = 'manager-feedback';
        }

        function createUploadEntry(file) {
          return {
            id: [file.name, file.size, file.lastModified, Math.random().toString(36).slice(2)].join('::'),
            file: file,
            name: file.name,
            sizeBytes: file.size,
            sizeLabel: formatKilobytes(file.size),
            modifiedLabel: formatDate(file.lastModified),
            modifiedIso: new Date(file.lastModified).toISOString(),
            previewUrl: URL.createObjectURL(file),
            state: getSizeState(file.size)
          };
        }

        function releaseUploadEntries(entries) {
          entries.forEach(function (entry) {
            if (entry && entry.previewUrl) {
              URL.revokeObjectURL(entry.previewUrl);
            }
          });
        }

        function getCurrentUploadItem() {
          if (state.files.length === 0) {
            return null;
          }

          state.currentUploadIndex = Math.max(0, Math.min(state.currentUploadIndex, state.files.length - 1));
          return state.files[state.currentUploadIndex];
        }

        function getCurrentDeleteItem() {
          if (state.existingImages.length === 0) {
            return null;
          }

          state.currentDeleteIndex = Math.max(0, Math.min(state.currentDeleteIndex, state.existingImages.length - 1));
          return state.existingImages[state.currentDeleteIndex];
        }

        function getCurrentItem() {
          return state.mode === 'upload' ? getCurrentUploadItem() : getCurrentDeleteItem();
        }

        function getCurrentCollectionSize() {
          return state.mode === 'upload' ? state.files.length : state.existingImages.length;
        }

        function getCurrentDestination(entry) {
          const folder = sanitizeFolder(folderInput.value || config.defaultFolder);
          return folder ? folder + '/' + entry.name : entry.name;
        }

        function sortExistingImages() {
          state.existingImages.sort(function (left, right) {
            return left.path.localeCompare(right.path);
          });
        }

        function updateButtons() {
          const collectionSize = getCurrentCollectionSize();
          const currentItem = getCurrentItem();
          const hasBlockedFiles = state.files.some(function (entry) {
            return entry.state === 'error';
          });
          const warningCount = state.files.filter(function (entry) {
            return entry.state === 'warning';
          }).length;

          prevButton.disabled = state.busy || collectionSize <= 1;
          nextButton.disabled = state.busy || collectionSize <= 1;
          closeButton.disabled = state.busy;

          modeTabs.forEach(function (tab) {
            tab.disabled = state.busy;
            tab.classList.toggle('is-active', tab.getAttribute('data-mode-tab') === state.mode);
          });

          pickFilesButton.disabled = state.busy;
          clearFilesButton.disabled = state.busy || state.files.length === 0;
          uploadButton.disabled = state.busy || state.files.length === 0 || hasBlockedFiles;
          deleteCurrentButton.disabled = state.busy || !currentItem || state.mode !== 'delete';
          openCurrentImageLink.setAttribute('aria-disabled', currentItem ? 'false' : 'true');
          openCurrentImageLink.style.pointerEvents = currentItem && state.mode === 'delete' ? 'auto' : 'none';
          openCurrentImageLink.style.opacity = currentItem && state.mode === 'delete' ? '1' : '0.45';

          if (state.mode === 'upload') {
            if (state.files.length === 0) {
              selectionSummary.textContent = 'No files selected yet.';
              statusNote.textContent = 'Choose files or drag them into the manager.';
            }
            else if (hasBlockedFiles) {
              selectionSummary.textContent = 'At least one selected file is above 200 KB and must be optimized.';
              statusNote.textContent = 'Upload is blocked until oversized files are removed or compressed.';
            }
            else {
              selectionSummary.textContent = state.files.length + ' file(s) selected' + (warningCount > 0 ? ', ' + warningCount + ' marked as large.' : '.');
              statusNote.textContent = 'Upload will create one image-only commit and trigger a fresh deploy.';
            }
          }
          else {
            deleteSummary.textContent = currentItem
              ? 'Delete "' + currentItem.name + '" from the repository with one separate commit.'
              : 'No published images are available to delete.';
            statusNote.textContent = currentItem
              ? 'Deletion removes the currently selected image and starts a new deploy.'
              : 'Nothing available to delete right now.';
          }
        }

        function renderPreview() {
          const currentItem = getCurrentItem();
          if (!currentItem) {
            previewWindow.innerHTML = '<div class="preview-placeholder"><strong>No image selected</strong><span>Add files in upload mode or choose an existing image in delete mode.</span></div>';
            return;
          }

          const previewUrl = state.mode === 'upload' ? currentItem.previewUrl : currentItem.publicUrl;
          const badgeMarkup = currentItem.state === 'ok'
            ? ''
            : '<div class="preview-badge ' + currentItem.state + '">' + escapeHtml(getStateLabel(currentItem.state)) + '</div>';

          previewWindow.innerHTML = badgeMarkup + '<img class="preview-asset" src="' + escapeHtml(previewUrl) + '" alt="' + escapeHtml(currentItem.name) + '">';
        }

        function renderMeta() {
          const currentItem = getCurrentItem();
          if (!currentItem) {
            previewMeta.innerHTML = '<div class="meta-pair"><span>Status</span><strong>Nothing selected</strong></div>';
            return;
          }

          const pairs = state.mode === 'upload'
            ? [
                ['Name', currentItem.name],
                ['Size', currentItem.sizeLabel],
                ['Date', currentItem.modifiedLabel],
                ['Destination', getCurrentDestination(currentItem)]
              ]
            : [
                ['Name', currentItem.name],
                ['Size', currentItem.sizeLabel],
                ['Date', currentItem.modifiedLabel],
                ['Path', currentItem.path]
              ];

          previewMeta.innerHTML = pairs.map(function (pair) {
            return '<div class="meta-pair"><span>' + escapeHtml(pair[0]) + '</span><strong>' + escapeHtml(pair[1]) + '</strong></div>';
          }).join('');
        }

        function renderThumbStrip() {
          const items = state.mode === 'upload' ? state.files : state.existingImages;
          const activeIndex = state.mode === 'upload' ? state.currentUploadIndex : state.currentDeleteIndex;

          if (items.length === 0) {
            thumbStrip.innerHTML = '<div class="strip-empty">' + (state.mode === 'upload'
              ? 'Your selected files will appear here.'
              : 'There are no published images available for deletion yet.') + '</div>';
            return;
          }

          thumbStrip.innerHTML = items.map(function (item, index) {
            const previewUrl = state.mode === 'upload' ? item.previewUrl : item.publicUrl;
            const cardClass = ['thumb-card', item.state];
            if (index === activeIndex) {
              cardClass.push('is-active');
            }

            const removeButton = state.mode === 'upload'
              ? '<button class="thumb-remove" type="button" data-remove-upload="' + escapeHtml(item.id) + '" aria-label="Remove selected file">&times;</button>'
              : '';

            return '<article class="' + cardClass.join(' ') + '" data-thumb-index="' + index + '">' +
              removeButton +
              '<img src="' + escapeHtml(previewUrl) + '" alt="' + escapeHtml(item.name) + '">' +
              '<span class="thumb-label">' + escapeHtml(item.name) + '</span>' +
              '<span class="thumb-sub">' + escapeHtml(item.sizeLabel) + ' / ' + escapeHtml(item.modifiedLabel) + '</span>' +
              '</article>';
          }).join('');
        }

        function renderModeCopy() {
          if (state.mode === 'upload') {
            controlTitle.textContent = 'Upload images';
            controlHint.textContent = 'Select new files, review them on the left, then commit them straight into the repository.';
            targetLabel.textContent = 'Destination folder';
            folderInput.readOnly = false;
            folderInput.placeholder = 'uploads or movies';
            if (!folderInput.value.trim()) {
              folderInput.value = config.defaultFolder;
            }
            modeNote.textContent = 'Files larger than 100 KB stay allowed and are marked as large. Files larger than 200 KB are blocked before upload.';
            uploadControls.hidden = false;
            deleteControls.hidden = true;
            uploadButton.hidden = false;
          }
          else {
            const currentDeleteItem = getCurrentDeleteItem();
            controlTitle.textContent = 'Delete published images';
            controlHint.textContent = 'Pick an existing image on the left and remove it with a dedicated delete commit.';
            targetLabel.textContent = 'Selected image path';
            folderInput.readOnly = true;
            folderInput.value = currentDeleteItem ? currentDeleteItem.path : '';
            modeNote.textContent = 'Deletion removes the selected file from the repository and triggers a new GitHub Pages deploy.';
            uploadControls.hidden = true;
            deleteControls.hidden = false;
            uploadButton.hidden = true;
          }
        }

        function renderManager() {
          renderModeCopy();
          renderPreview();
          renderMeta();
          renderThumbStrip();

          const currentDeleteItem = getCurrentDeleteItem();
          openCurrentImageLink.href = currentDeleteItem ? currentDeleteItem.publicUrl : '#';

          if (state.mode === 'upload') {
            folderInput.value = folderInput.value.trim() ? folderInput.value : config.defaultFolder;
          }

          updateButtons();
        }

        function mergeFiles(fileList) {
          const nextFiles = state.files.slice();
          const seen = new Set(nextFiles.map(function (entry) {
            return entry.name + '::' + entry.sizeBytes + '::' + entry.file.lastModified;
          }));

          Array.from(fileList).forEach(function (file) {
            const key = file.name + '::' + file.size + '::' + file.lastModified;
            if (!seen.has(key)) {
              seen.add(key);
              nextFiles.push(createUploadEntry(file));
            }
          });

          state.files = nextFiles;
          if (state.files.length > 0) {
            state.currentUploadIndex = state.files.length - 1;
          }
          clearFeedback();
          renderManager();
        }

        function removeUploadEntry(entryId) {
          const removedEntries = state.files.filter(function (entry) {
            return entry.id === entryId;
          });

          releaseUploadEntries(removedEntries);
          state.files = state.files.filter(function (entry) {
            return entry.id !== entryId;
          });
          state.currentUploadIndex = Math.max(0, Math.min(state.currentUploadIndex, state.files.length - 1));
          renderManager();
        }

        function clearUploadSelection() {
          releaseUploadEntries(state.files);
          state.files = [];
          state.currentUploadIndex = 0;
          fileInput.value = '';
          clearFeedback();
          renderManager();
        }

        function openModal(mode, imagePath) {
          if (mode) {
            state.mode = mode;
          }

          if (imagePath && state.mode === 'delete') {
            const matchIndex = state.existingImages.findIndex(function (image) {
              return image.path === imagePath;
            });
            if (matchIndex >= 0) {
              state.currentDeleteIndex = matchIndex;
            }
          }

          syncSuggestedCommitMessage(false);
          clearFeedback();
          modal.classList.add('is-open');
          modal.setAttribute('aria-hidden', 'false');
          renderManager();
        }

        function closeModal() {
          if (state.busy) {
            return;
          }

          modal.classList.remove('is-open');
          modal.setAttribute('aria-hidden', 'true');
        }

        function setMode(mode) {
          if (state.busy) {
            return;
          }

          state.mode = mode;
          syncSuggestedCommitMessage(false);
          clearFeedback();
          renderManager();
        }

        async function githubRequest(path, options, token) {
          const response = await fetch('https://api.github.com' + path, {
            method: options.method || 'GET',
            headers: {
              'Accept': 'application/vnd.github+json',
              'Authorization': 'Bearer ' + token,
              'X-GitHub-Api-Version': '2022-11-28',
              'Content-Type': 'application/json'
            },
            body: options.body ? JSON.stringify(options.body) : undefined
          });

          if (!response.ok) {
            let message = 'GitHub API request failed.';
            try {
              const data = await response.json();
              if (data && data.message) {
                message = data.message;
              }
            } catch (error) {
            }

            throw new Error(message);
          }

          if (response.status === 204) {
            return {};
          }

          return response.json();
        }

        async function fileToBase64(file) {
          const buffer = await file.arrayBuffer();
          const bytes = new Uint8Array(buffer);
          const chunkSize = 32768;
          let binary = '';

          for (let index = 0; index < bytes.length; index += chunkSize) {
            const chunk = bytes.subarray(index, index + chunkSize);
            binary += String.fromCharCode.apply(null, chunk);
          }

          return btoa(binary);
        }

        async function uploadFiles() {
          const token = tokenInput.value.trim();
          const commitMessage = commitMessageInput.value.trim() || getSuggestedCommitMessage();

          if (!config.owner || !config.repo) {
            throw new Error('Repository information is missing from this page configuration.');
          }

          if (!token) {
            throw new Error('Add a GitHub token before uploading.');
          }

          if (state.files.length === 0) {
            throw new Error('Choose at least one image to upload.');
          }

          const blockedFile = state.files.find(function (entry) {
            return entry.state === 'error';
          });
          if (blockedFile) {
            throw new Error('The file "' + blockedFile.name + '" is larger than 200 KB.');
          }

          const finalPaths = state.files.map(function (entry) {
            return getCurrentDestination(entry);
          });

          if ((new Set(finalPaths)).size !== finalPaths.length) {
            throw new Error('Two selected files resolve to the same destination path.');
          }

          setFeedback('info', 'Uploading files to GitHub...');

          const refName = encodeURIComponent(config.branch);
          const refData = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/ref/heads/' + refName, {}, token);
          const headSha = refData.object.sha;
          const commitData = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/commits/' + headSha, {}, token);
          const baseTreeSha = commitData.tree.sha;

          const entries = [];
          for (let index = 0; index < state.files.length; index += 1) {
            const entry = state.files[index];
            const blob = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/blobs', {
              method: 'POST',
              body: {
                content: await fileToBase64(entry.file),
                encoding: 'base64'
              }
            }, token);

            entries.push({
              path: finalPaths[index],
              mode: '100644',
              type: 'blob',
              sha: blob.sha
            });
          }

          const tree = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/trees', {
            method: 'POST',
            body: {
              base_tree: baseTreeSha,
              tree: entries
            }
          }, token);

          const commit = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/commits', {
            method: 'POST',
            body: {
              message: commitMessage,
              tree: tree.sha,
              parents: [headSha]
            }
          }, token);

          await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/refs/heads/' + refName, {
            method: 'PATCH',
            body: {
              sha: commit.sha,
              force: false
            }
          }, token);

          const nowIso = new Date().toISOString();
          const uploadedEntries = state.files.map(function (entry, index) {
            const finalPath = finalPaths[index];
            const encodedPath = encodePathSegments(finalPath);
            return {
              name: entry.name,
              path: finalPath,
              urlPath: encodedPath,
              publicUrl: './' + encodedPath,
              sizeBytes: entry.sizeBytes,
              sizeLabel: entry.sizeLabel,
              modifiedLabel: formatDate(nowIso),
              modifiedIso: nowIso,
              state: entry.state
            };
          });

          const uploadedPathSet = new Set(uploadedEntries.map(function (entry) {
            return entry.path;
          }));

          state.existingImages = state.existingImages.filter(function (entry) {
            return !uploadedPathSet.has(entry.path);
          }).concat(uploadedEntries);
          sortExistingImages();

          const uploadedSummary = uploadedEntries.map(function (entry) {
            return entry.path;
          }).join(', ');

          clearUploadSelection();
          setFeedback('success', 'Upload committed successfully. GitHub Pages will refresh after deployment. Uploaded: ' + uploadedSummary);
          renderManager();
        }

        async function deleteCurrentImage() {
          const token = tokenInput.value.trim();
          const commitMessage = commitMessageInput.value.trim() || getSuggestedCommitMessage();
          const currentItem = getCurrentDeleteItem();

          if (!currentItem) {
            throw new Error('Choose an existing image before deleting.');
          }

          if (!token) {
            throw new Error('Add a GitHub token before deleting.');
          }

          const encodedContentPath = encodePathSegments(currentItem.path);
          setFeedback('info', 'Deleting the selected image from GitHub...');

          const fileData = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/contents/' + encodedContentPath + '?ref=' + encodeURIComponent(config.branch), {}, token);
          await githubRequest('/repos/' + config.owner + '/' + config.repo + '/contents/' + encodedContentPath, {
            method: 'DELETE',
            body: {
              message: commitMessage,
              sha: fileData.sha,
              branch: config.branch
            }
          }, token);

          state.existingImages = state.existingImages.filter(function (entry) {
            return entry.path !== currentItem.path;
          });
          state.currentDeleteIndex = Math.max(0, Math.min(state.currentDeleteIndex, state.existingImages.length - 1));
          setFeedback('success', 'Delete committed successfully. GitHub Pages will refresh after deployment. Removed: ' + currentItem.path);
          renderManager();
        }

        openButton.addEventListener('click', function () {
          openModal('upload');
        });

        closeButton.addEventListener('click', closeModal);
        modal.addEventListener('click', function (event) {
          if (event.target === modal) {
            closeModal();
          }
        });

        document.addEventListener('keydown', function (event) {
          if (event.key === 'Escape') {
            closeModal();
          }
        });

        document.addEventListener('click', function (event) {
          const manageTrigger = event.target.closest('[data-open-manager]');
          if (!manageTrigger) {
            return;
          }

          event.preventDefault();
          openModal(manageTrigger.getAttribute('data-open-manager') || 'upload', manageTrigger.getAttribute('data-image-path') || '');
        });

        modeTabs.forEach(function (tab) {
          tab.addEventListener('click', function () {
            setMode(tab.getAttribute('data-mode-tab'));
          });
        });

        prevButton.addEventListener('click', function () {
          if (state.mode === 'upload' && state.files.length > 1) {
            state.currentUploadIndex = (state.currentUploadIndex - 1 + state.files.length) % state.files.length;
          }
          else if (state.mode === 'delete' && state.existingImages.length > 1) {
            state.currentDeleteIndex = (state.currentDeleteIndex - 1 + state.existingImages.length) % state.existingImages.length;
          }

          renderManager();
        });

        nextButton.addEventListener('click', function () {
          if (state.mode === 'upload' && state.files.length > 1) {
            state.currentUploadIndex = (state.currentUploadIndex + 1) % state.files.length;
          }
          else if (state.mode === 'delete' && state.existingImages.length > 1) {
            state.currentDeleteIndex = (state.currentDeleteIndex + 1) % state.existingImages.length;
          }

          renderManager();
        });

        thumbStrip.addEventListener('click', function (event) {
          const removeButton = event.target.closest('[data-remove-upload]');
          if (removeButton) {
            event.stopPropagation();
            removeUploadEntry(removeButton.getAttribute('data-remove-upload'));
            return;
          }

          const thumbCard = event.target.closest('[data-thumb-index]');
          if (!thumbCard) {
            return;
          }

          const thumbIndex = Number(thumbCard.getAttribute('data-thumb-index'));
          if (Number.isNaN(thumbIndex)) {
            return;
          }

          if (state.mode === 'upload') {
            state.currentUploadIndex = thumbIndex;
          }
          else {
            state.currentDeleteIndex = thumbIndex;
          }

          renderManager();
        });

        pickFilesButton.addEventListener('click', function () {
          fileInput.click();
        });

        fileInput.addEventListener('change', function (event) {
          mergeFiles(event.target.files);
        });

        folderInput.addEventListener('input', function () {
          if (state.mode === 'upload') {
            renderManager();
          }
        });

        ['dragenter', 'dragover'].forEach(function (eventName) {
          dropzone.addEventListener(eventName, function (event) {
            event.preventDefault();
            dropzone.classList.add('is-active');
          });
        });

        ['dragleave', 'drop'].forEach(function (eventName) {
          dropzone.addEventListener(eventName, function (event) {
            event.preventDefault();
            if (eventName === 'drop') {
              mergeFiles(event.dataTransfer.files);
            }
            dropzone.classList.remove('is-active');
          });
        });

        clearFilesButton.addEventListener('click', function () {
          if (!state.busy) {
            clearUploadSelection();
          }
        });

        uploadButton.addEventListener('click', async function () {
          if (state.busy) {
            return;
          }

          state.busy = true;
          renderManager();

          try {
            await uploadFiles();
          } catch (error) {
            setFeedback('error', error.message || 'Upload failed.');
          } finally {
            state.busy = false;
            renderManager();
          }
        });

        deleteCurrentButton.addEventListener('click', async function () {
          if (state.busy) {
            return;
          }

          state.busy = true;
          renderManager();

          try {
            await deleteCurrentImage();
          } catch (error) {
            setFeedback('error', error.message || 'Delete failed.');
          } finally {
            state.busy = false;
            renderManager();
          }
        });

        sortExistingImages();
        syncSuggestedCommitMessage(true);
        renderManager();
      }());
    </script>
  </body>
</html>
"@

[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $outputPath with $imageCount image(s)."
