# Bluesky

Inkstead Writer can publish posts directly to Bluesky.

Required environment variables:

- `BLUESKY_IDENTIFIER`
- `BLUESKY_APP_PASSWORD`

`BLUESKY_IDENTIFIER` is usually your handle, such as `example.com` or `you.bsky.social`. Use an app password rather than your main account password; create one in Bluesky under Settings, then Privacy and Security, then App Passwords.

Bluesky posts are limited to 300 characters. When a titled post would run over, Inkstead Writer shortens the title and keeps the canonical URL intact.

Bluesky photo notes embed up to four images.
