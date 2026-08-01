# Pixelfed

Pixelfed is a photo sharing service, so Inkstead Writer sends only photo notes there. If you have a Pixelfed account, connecting takes two settings and a token you create once.

Inkstead Writer reads two environment variables:

| Variable | What it is |
| --- | --- |
| `PIXELFED_INSTANCE_URL` | The address of your instance |
| `PIXELFED_ACCESS_TOKEN` | The token that lets Inkstead Writer post as you |

Set them in your site's `.env` file for local publishing, or as CI secrets or variables:

```env
PIXELFED_INSTANCE_URL=https://pixelfed.social
PIXELFED_ACCESS_TOKEN=...
```

## Getting an access token

Open your Pixelfed account settings, go to Applications and create a personal access token with write access.

## What gets posted

Pixelfed requires media, so only photo notes syndicate there. The attached photos upload with the note text as the caption.

Add `pixelfed` to a photo note when you want that note to publish to Pixelfed:

```yaml
syndicate:
  - pixelfed
```

See [Syndication](index.md) for how results are recorded and how to retry a failure.
