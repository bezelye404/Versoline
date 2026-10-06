# Versoline website

A static one-page site for GitHub Pages: plain HTML and CSS, no scripts, no external fonts, no trackers.

## Publish

1. In the repository, open **Settings > Pages** and set **Source** to **GitHub Actions**.
2. Push to `main`. The `Pages` workflow (`.github/workflows/pages.yml`) publishes this folder whenever a file in `website/` changes. It can also be started by hand from the Actions tab.

The site is served at `https://bezelye404.github.io/Versoline/`. If you later use a custom domain, update the URLs in `index.html` (`canonical`, `og:url`, `og:image`, the JSON-LD block), `robots.txt` and `sitemap.xml`.

## After it is live

- Add the site to Google Search Console and Bing Webmaster Tools and submit `sitemap.xml`.
- Add screenshots to `assets/` and uncomment the screenshots section in `index.html`.
- Update `lastmod` in `sitemap.xml` when the content changes.
