# Pixelfed

Inkstead Writer can syndicate photo notes to Pixelfed.

Required environment variables:

- `PIXELFED_INSTANCE_URL`
- `PIXELFED_ACCESS_TOKEN`

Example:

```env
PIXELFED_INSTANCE_URL=https://pixelfed.social
PIXELFED_ACCESS_TOKEN=...
```

To get a token, open your Pixelfed account settings, go to Applications, and create a personal access token with write access.

Pixelfed requires media, so only photo notes syndicate there. Attached photos upload with the note text as the caption.

Add `pixelfed` to a photo note when you want that note to publish to Pixelfed:

```yaml
syndicate:
  - pixelfed
```
