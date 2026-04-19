# moontake website

Static marketing site for `moontake`, with:

- Multilingual landing pages
- Shared dark theme
- App Store CTA
- iPhone Safari download banner
- `robots.txt`, `sitemap.xml`, and structured metadata
- A simple Caddy config example

## Structure

- `/index.html`: English default page
- `/zh/index.html`: Simplified Chinese page
- `/ja/index.html`: Japanese page
- `/assets/css/styles.css`: shared styles
- `/assets/js/site.js`: iPhone Safari banner logic

## Deploy with Caddy on Ubuntu

1. Copy the static files to the server:

   ```bash
   sudo mkdir -p /var/www/moontake
   sudo rsync -av --delete website/ /var/www/moontake/
   ```

2. Put the Caddy config in place:

   ```bash
   sudo cp website/Caddyfile.example /etc/caddy/Caddyfile
   sudo caddy fmt --overwrite /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

3. Make sure DNS for `moontake.com` and `www.moontake.com` points to the server.

4. Test:

   ```bash
   curl -I https://moontake.com
   curl -I https://moontake.com/zh/
   curl -I https://moontake.com/ja/
   curl -I https://moontake.com/zh-hant/
   ```

## Notes

- The App Store link currently points to `https://apps.apple.com/app/id6451189717`.
- iPhone Safari will get both the Apple smart app banner meta tag and a custom bottom banner.
