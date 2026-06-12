# Mastodon

Inkstead Writer can publish posts directly to Mastodon.

Required environment variables:

- `MASTODON_INSTANCE_URL`
- `MASTODON_ACCESS_TOKEN`

Example:

```env
MASTODON_INSTANCE_URL=https://mastodon.social
MASTODON_ACCESS_TOKEN=...
```

## Get An Access Token

On your instance, open Preferences, then Development, then New application. Name it anything you like, give it the `write:statuses` and `write:media` scopes, and save. Copy the access token from the application page.

## What Gets Posted

Titled posts syndicate as title plus canonical URL. Notes post their text as-is; most instances limit posts to 500 characters.

Photo notes upload attached photos. Inkstead Writer reads your instance's image size limits and prepares photos to fit before uploading, so large originals work without any manual resizing.
