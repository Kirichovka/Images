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

      @media (max-width: 640px) {
        .shell {
          width: min(100% - 20px, 1200px);
          padding: 20px 0 40px;
        }

        .hero-inner {
          padding: 24px 20px;
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
            Every file in this repository is published as a static asset. Open any preview to get a direct public URL you can use on your website.
          </p>
          <div class="stats">
            <div class="stat">$imageCount image(s)</div>
            <div class="stat">Updated $lastUpdated</div>
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
  </body>
</html>
"@

[System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $outputPath with $imageCount image(s)."
