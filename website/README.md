# Versoline website

A static site for GitHub Pages (English at `/`, Turkish at `/tr/`): plain HTML and CSS plus one small script (`site.js`) for the copy buttons and the palette preview. No external fonts, no trackers, nothing loaded from other servers; the Content-Security-Policy in each page allows only its own files.

## Publish

1. In the repository, open **Settings > Pages** and set **Source** to **GitHub Actions**.
2. Push to `main`. The `Pages` workflow (`.github/workflows/pages.yml`) publishes this folder whenever a file in `website/` changes. It can also be started by hand from the Actions tab.

The site is served at `https://bezelye404.github.io/Versoline/`. If you later use a custom domain, update the URLs in `index.html` (`canonical`, `og:url`, `og:image`, the JSON-LD block), `robots.txt` and `sitemap.xml`.

## After it is live

- Add the site to Google Search Console and Bing Webmaster Tools and submit `sitemap.xml`.
- Add screenshots to `assets/` and uncomment the screenshots section in `index.html`.
- Update `lastmod` in `sitemap.xml` when the content changes.
