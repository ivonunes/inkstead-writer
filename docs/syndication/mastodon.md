# Mastodon

If you have a Mastodon account, Inkstead Writer can post to it whenever you publish. Connecting takes two settings and a token you create once on your instance (the Mastodon server your account lives on).

Inkstead Writer reads two environment variables:

| Variable | What it is |
| --- | --- |
| `MASTODON_INSTANCE_URL` | The address of your instance |
| `MASTODON_ACCESS_TOKEN` | The token that lets Inkstead Writer post as you |

Set them in your site's `.env` file for local publishing, or as CI secrets or variables:

```env
MASTODON_INSTANCE_URL=https://mastodon.social
MASTODON_ACCESS_TOKEN=...
```

## Getting an access token

On your instance, open Preferences, then Development, then New application. Name it anything you like, give it the `write:statuses` and `write:media` scopes (the permissions to post and to upload images) and save. Copy the access token from the application page.

## What gets posted

Titled posts go out as the title plus a link to the post on your site. Notes post their text as-is; most instances limit posts to 500 characters.

Photo notes upload their attached photos. Inkstead Writer asks your instance for its image size limits and prepares photos to fit before uploading, so large originals work without any manual resizing.

See [Syndication](index.md) for how posts opt in and how results are recorded.
