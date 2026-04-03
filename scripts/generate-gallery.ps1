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

$images = Get-ChildItem -Path $resolvedRepoRoot -Recurse -File |
    Where-Object {
        $relativePath = Get-RelativeWebPath -BasePath $resolvedRepoRoot -TargetPath $_.FullName
        $normalizedRelativePath = $relativePath.Replace("\", "/")

        $supportedExtensions -contains $_.Extension.ToLowerInvariant() -and
        $normalizedRelativePath -notmatch '^(?:\.git|\.github|scripts)/'
    } |
    Sort-Object FullName

$galleryItems = foreach ($image in $images) {
    $relativePath = Get-RelativeWebPath -BasePath $resolvedRepoRoot -TargetPath $image.FullName
    $urlPath = Convert-ToUrlPath -RelativePath $relativePath
    $displayPath = Convert-ToHtmlText($relativePath.Replace("\", "/"))
    $displayName = Convert-ToHtmlText($image.Name)
    $displaySize = "{0:N1} KB" -f ($image.Length / 1KB)
    $sizeState = Get-SizeState -Length $image.Length
    $cardClass = "card"
    $noticeMarkup = ""

    if ($sizeState -eq "warning") {
        $cardClass = "card card-warning"
        $noticeMarkup = '<p class="size-notice" aria-label="Large file warning">Warning: file is larger than 100 KB and may slow down your site.</p>'
    }
    elseif ($sizeState -eq "error") {
        $cardClass = "card card-error"
        $noticeMarkup = '<p class="size-notice" aria-label="File too large">Error: file is larger than 200 KB and should be optimized before publishing.</p>'
    }

@"
        <article class="$cardClass">
          <a class="preview" href="./$urlPath" target="_blank" rel="noreferrer">
            <img src="./$urlPath" alt="$displayName" loading="lazy">
          </a>
          <div class="meta">
            <h2>$displayName</h2>
            <p class="path">$displayPath</p>
            <p class="size">$displaySize</p>
            $noticeMarkup
            <a class="direct-link" href="./$urlPath" target="_blank" rel="noreferrer">Open direct link</a>
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

      .direct-link {
        width: fit-content;
        text-decoration: none;
        color: white;
        background: linear-gradient(135deg, var(--accent), var(--accent-strong));
        padding: 10px 14px;
        border-radius: 999px;
        font-size: 14px;
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

      .modal-shell {
        position: fixed;
        inset: 0;
        display: none;
        align-items: center;
        justify-content: center;
        padding: 18px;
        background: rgba(28, 20, 15, 0.56);
        backdrop-filter: blur(8px);
        z-index: 20;
      }

      .modal-shell.is-open {
        display: flex;
      }

      .modal-card {
        width: min(920px, 100%);
        max-height: min(90vh, 980px);
        overflow: auto;
        background: #fffdf8;
        border-radius: 28px;
        border: 1px solid rgba(52, 36, 24, 0.12);
        box-shadow: 0 30px 80px rgba(28, 20, 15, 0.26);
      }

      .modal-head {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        padding: 24px 24px 0;
      }

      .modal-head h3 {
        margin: 0;
        font-size: 30px;
      }

      .modal-head p {
        margin: 10px 0 0;
        color: var(--muted);
        line-height: 1.6;
      }

      .modal-body {
        padding: 24px;
        display: grid;
        gap: 18px;
      }

      .upload-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 16px;
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
        padding: 13px 14px;
        border-radius: 16px;
        border: 1px solid rgba(52, 36, 24, 0.12);
        background: rgba(255, 255, 255, 0.86);
        color: var(--text);
        font: inherit;
      }

      .dropzone {
        border-radius: 24px;
        border: 2px dashed rgba(217, 93, 57, 0.26);
        background:
          linear-gradient(135deg, rgba(255, 246, 237, 0.9), rgba(255, 252, 247, 0.92));
        padding: 28px;
        text-align: center;
        display: grid;
        gap: 10px;
      }

      .dropzone.is-active {
        border-color: rgba(217, 93, 57, 0.6);
        background:
          linear-gradient(135deg, rgba(255, 239, 227, 0.98), rgba(255, 251, 243, 0.95));
      }

      .dropzone strong {
        font-size: 20px;
      }

      .dropzone p {
        margin: 0;
        color: var(--muted);
      }

      .inline-note,
      .upload-feedback {
        margin: 0;
        padding: 12px 14px;
        border-radius: 16px;
        font-size: 14px;
        line-height: 1.5;
      }

      .inline-note {
        background: rgba(255, 245, 230, 0.8);
        border: 1px solid rgba(217, 93, 57, 0.16);
        color: var(--muted);
      }

      .upload-feedback {
        display: none;
      }

      .upload-feedback.is-visible {
        display: block;
      }

      .upload-feedback.info {
        background: rgba(255, 245, 230, 0.9);
        border: 1px solid rgba(217, 93, 57, 0.18);
        color: var(--text);
      }

      .upload-feedback.success {
        background: rgba(231, 247, 236, 0.92);
        border: 1px solid rgba(55, 130, 83, 0.18);
        color: #245736;
      }

      .upload-feedback.error {
        background: rgba(255, 233, 228, 0.96);
        border: 1px solid rgba(175, 57, 36, 0.2);
        color: #8a2d16;
      }

      .selected-files {
        display: grid;
        gap: 12px;
      }

      .selected-file {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 14px;
        align-items: center;
        padding: 14px 16px;
        border-radius: 18px;
        border: 1px solid rgba(52, 36, 24, 0.1);
        background: rgba(255, 255, 255, 0.86);
      }

      .selected-file strong,
      .selected-file span {
        display: block;
      }

      .selected-file strong {
        font-size: 16px;
      }

      .selected-file span {
        margin-top: 4px;
        color: var(--muted);
        font-size: 14px;
        line-height: 1.45;
      }

      .selected-file .badge {
        border-radius: 999px;
        padding: 8px 12px;
        font-size: 12px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        white-space: nowrap;
        border: 1px solid rgba(52, 36, 24, 0.1);
        background: rgba(242, 239, 235, 0.9);
      }

      .selected-file.warning {
        background: rgba(255, 247, 214, 0.9);
        border-color: rgba(184, 134, 11, 0.28);
      }

      .selected-file.warning .badge {
        background: rgba(244, 202, 68, 0.28);
        color: #725300;
        border-color: rgba(184, 134, 11, 0.22);
      }

      .selected-file.error {
        background: rgba(255, 233, 228, 0.94);
        border-color: rgba(175, 57, 36, 0.26);
      }

      .selected-file.error .badge {
        background: rgba(217, 93, 57, 0.16);
        color: #8a2d16;
        border-color: rgba(175, 57, 36, 0.22);
      }

      .modal-actions {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
      }

      .action-group {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
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

        .modal-head,
        .modal-body {
          padding-left: 18px;
          padding-right: 18px;
        }

        .selected-file {
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
            <button class="secondary-button" type="button" id="open-uploader">Upload images</button>
            <a class="ghost-button" href="https://github.com/$($githubRepoInfo.owner)/$($githubRepoInfo.repo)/actions" target="_blank" rel="noreferrer">View deploy status</a>
          </div>
        </div>
      </section>

      <section class="uploader-panel">
        <h2>Separate image uploads from code pushes.</h2>
        <p>
          The uploader creates a dedicated Git commit with your selected images, so you can publish assets from the browser without mixing them into your local code workflow.
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
    <div class="modal-shell" id="uploader-modal" aria-hidden="true">
      <div class="modal-card" role="dialog" aria-modal="true" aria-labelledby="uploader-title">
        <div class="modal-head">
          <div>
            <p class="eyebrow">Browser Uploader</p>
            <h3 id="uploader-title">Upload images to this repository</h3>
            <p>
              Use a fine-grained GitHub token with repository contents write access. The token stays only in this browser tab and is not saved by the page.
            </p>
          </div>
          <button class="ghost-button" type="button" id="close-uploader">Close</button>
        </div>
        <div class="modal-body">
          <div class="upload-grid">
            <div class="field">
              <label for="github-token">GitHub token</label>
              <input id="github-token" type="password" autocomplete="off" placeholder="github_pat_..." spellcheck="false">
            </div>
            <div class="field">
              <label for="target-folder">Target folder</label>
              <input id="target-folder" type="text" value="uploads" placeholder="uploads or movies">
            </div>
            <div class="field">
              <label for="commit-message">Commit message</label>
              <input id="commit-message" type="text" value="Upload images via gallery uploader" placeholder="Upload new images">
            </div>
          </div>

          <div class="dropzone" id="dropzone">
            <strong>Drop image files here</strong>
            <p>or</p>
            <div>
              <button class="secondary-button" type="button" id="pick-files">Choose files</button>
            </div>
            <p>Supported: PNG, JPG, JPEG, GIF, WEBP, SVG, AVIF</p>
            <input id="file-input" type="file" multiple accept=".png,.jpg,.jpeg,.gif,.webp,.svg,.avif,image/png,image/jpeg,image/gif,image/webp,image/svg+xml,image/avif" hidden>
          </div>

          <p class="inline-note">
            Files larger than 100 KB are allowed but marked as large. Files larger than 200 KB are blocked before upload.
          </p>

          <p class="upload-feedback" id="upload-feedback" role="status" aria-live="polite"></p>

          <section>
            <h4>Selected files</h4>
            <div class="selected-files" id="selected-files">
              <div class="empty-state">
                <p>No files selected yet.</p>
              </div>
            </div>
          </section>

          <div class="modal-actions">
            <div class="status-note" id="status-note">Nothing to upload yet.</div>
            <div class="action-group">
              <button class="ghost-button" type="button" id="clear-files">Clear</button>
              <button class="secondary-button" type="button" id="start-upload">Upload to repository</button>
            </div>
          </div>
        </div>
      </div>
    </div>
    <script>
      window.galleryConfig = $galleryConfigJson;

      (function () {
        const config = window.galleryConfig;
        const state = {
          files: [],
          uploading: false
        };

        const modal = document.getElementById('uploader-modal');
        const openButton = document.getElementById('open-uploader');
        const closeButton = document.getElementById('close-uploader');
        const pickFilesButton = document.getElementById('pick-files');
        const fileInput = document.getElementById('file-input');
        const dropzone = document.getElementById('dropzone');
        const selectedFiles = document.getElementById('selected-files');
        const clearFilesButton = document.getElementById('clear-files');
        const uploadButton = document.getElementById('start-upload');
        const feedback = document.getElementById('upload-feedback');
        const statusNote = document.getElementById('status-note');
        const tokenInput = document.getElementById('github-token');
        const folderInput = document.getElementById('target-folder');
        const commitMessageInput = document.getElementById('commit-message');

        function escapeHtml(value) {
          return value
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
        }

        function formatKilobytes(size) {
          return (size / 1024).toFixed(1) + ' KB';
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

        function getSizeDescription(file) {
          const stateName = getSizeState(file.size);
          if (stateName === 'error') {
            return 'Blocked: larger than 200 KB';
          }

          if (stateName === 'warning') {
            return 'Large file: larger than 100 KB';
          }

          return 'Ready';
        }

        function sanitizeFolder(value) {
          return value.replace(/\\/g, '/').replace(/^\/+|\/+$/g, '').replace(/\/{2,}/g, '/').trim();
        }

        function setFeedback(kind, message) {
          feedback.textContent = message;
          feedback.className = 'upload-feedback is-visible ' + kind;
        }

        function clearFeedback() {
          feedback.textContent = '';
          feedback.className = 'upload-feedback';
        }

        function updateButtons() {
          const hasFiles = state.files.length > 0;
          const hasBlockedFiles = state.files.some(function (file) {
            return getSizeState(file.size) === 'error';
          });

          uploadButton.disabled = state.uploading || !hasFiles || hasBlockedFiles;
          clearFilesButton.disabled = state.uploading || !hasFiles;

          if (!hasFiles) {
            statusNote.textContent = 'Nothing to upload yet.';
            return;
          }

          if (hasBlockedFiles) {
            statusNote.textContent = 'At least one file is above 200 KB and must be optimized before upload.';
            return;
          }

          const warningCount = state.files.filter(function (file) {
            return getSizeState(file.size) === 'warning';
          }).length;

          if (warningCount > 0) {
            statusNote.textContent = warningCount + ' file(s) are above 100 KB and will be marked as large.';
            return;
          }

          statusNote.textContent = 'All selected files are ready for upload.';
        }

        function renderFiles() {
          if (state.files.length === 0) {
            selectedFiles.innerHTML = '<div class="empty-state"><p>No files selected yet.</p></div>';
            updateButtons();
            return;
          }

          selectedFiles.innerHTML = state.files.map(function (file) {
            const stateName = getSizeState(file.size);
            const className = stateName === 'ok' ? 'selected-file' : 'selected-file ' + stateName;
            return '<article class="' + className + '">' +
              '<div><strong>' + escapeHtml(file.name) + '</strong><span>' + formatKilobytes(file.size) + ' · ' + escapeHtml(getSizeDescription(file)) + '</span></div>' +
              '<div class="badge">' + escapeHtml(stateName === 'ok' ? 'ready' : stateName) + '</div>' +
              '</article>';
          }).join('');

          updateButtons();
        }

        function mergeFiles(fileList) {
          const nextFiles = state.files.slice();
          const seen = new Set(nextFiles.map(function (file) {
            return file.name + '::' + file.size + '::' + file.lastModified;
          }));

          Array.from(fileList).forEach(function (file) {
            const key = file.name + '::' + file.size + '::' + file.lastModified;
            if (!seen.has(key)) {
              seen.add(key);
              nextFiles.push(file);
            }
          });

          state.files = nextFiles;
          clearFeedback();
          renderFiles();
        }

        function openModal() {
          modal.classList.add('is-open');
          modal.setAttribute('aria-hidden', 'false');
          clearFeedback();
        }

        function closeModal() {
          if (state.uploading) {
            return;
          }

          modal.classList.remove('is-open');
          modal.setAttribute('aria-hidden', 'true');
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
          const folder = sanitizeFolder(folderInput.value || config.defaultFolder);
          const commitMessage = (commitMessageInput.value || '').trim() || 'Upload images via gallery uploader';

          if (!config.owner || !config.repo) {
            throw new Error('Repository information is missing from this page configuration.');
          }

          if (!token) {
            throw new Error('Add a GitHub token before uploading.');
          }

          if (state.files.length === 0) {
            throw new Error('Choose at least one image to upload.');
          }

          const blockedFile = state.files.find(function (file) {
            return getSizeState(file.size) === 'error';
          });
          if (blockedFile) {
            throw new Error('The file "' + blockedFile.name + '" is larger than 200 KB.');
          }

          const finalPaths = state.files.map(function (file) {
            return folder ? folder + '/' + file.name : file.name;
          });

          if ((new Set(finalPaths)).size !== finalPaths.length) {
            throw new Error('Two selected files resolve to the same target path.');
          }

          setFeedback('info', 'Uploading files to GitHub...');

          const refName = encodeURIComponent(config.branch);
          const refData = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/ref/heads/' + refName, {}, token);
          const headSha = refData.object.sha;
          const commitData = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/commits/' + headSha, {}, token);
          const baseTreeSha = commitData.tree.sha;

          const entries = [];
          for (let index = 0; index < state.files.length; index += 1) {
            const file = state.files[index];
            const blob = await githubRequest('/repos/' + config.owner + '/' + config.repo + '/git/blobs', {
              method: 'POST',
              body: {
                content: await fileToBase64(file),
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

          const uploadedSummary = finalPaths.join(', ');
          setFeedback('success', 'Upload committed successfully. GitHub Pages will refresh after deployment. Uploaded: ' + uploadedSummary);
          state.files = [];
          fileInput.value = '';
          renderFiles();
        }

        openButton.addEventListener('click', openModal);
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

        pickFilesButton.addEventListener('click', function () {
          fileInput.click();
        });

        fileInput.addEventListener('change', function (event) {
          mergeFiles(event.target.files);
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
          if (state.uploading) {
            return;
          }

          state.files = [];
          fileInput.value = '';
          clearFeedback();
          renderFiles();
        });

        uploadButton.addEventListener('click', async function () {
          if (state.uploading) {
            return;
          }

          state.uploading = true;
          updateButtons();

          try {
            await uploadFiles();
          } catch (error) {
            setFeedback('error', error.message || 'Upload failed.');
          } finally {
            state.uploading = false;
            updateButtons();
          }
        });

        renderFiles();
      }());
    </script>
  </body>
</html>
"@

[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $outputPath with $imageCount image(s)."
