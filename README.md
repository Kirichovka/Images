# Images

This repository publishes images through GitHub Pages so they can be used as direct URLs on a website.

## How it works

- Every push to `main` rebuilds `index.html` and deploys the repository to GitHub Pages.
- A pre-push size check blocks the push only when changed images are larger than `200 KB`.
- Root files become available as `/filename.ext`.
- Files in folders become available as `/folder/filename.ext`.

## Expected public URLs

After GitHub Pages is enabled for this repository, the images will be available at:

- `https://kirichovka.github.io/Images/`
- `https://kirichovka.github.io/Images/4DX.png`
- `https://kirichovka.github.io/Images/movies/Steel-Horizon-movie_facke_img_action_thriller.webp`

## Adding new images

1. Add files anywhere in the repository except `.github` and `scripts`.
2. Push to `main`.
3. Wait for the `Deploy GitHub Pages` workflow to finish.

The gallery page is generated automatically by `scripts/generate-gallery.ps1`.

## Size rules

- `> 100 KB`: allowed on push, but highlighted in yellow on the gallery page.
- `> 200 KB`: error, but only for images included in the current push. Existing old files do not block unrelated pushes.
