# Mastodon

Inkstead can publish posts directly to Mastodon.

Required environment variables:

- `MASTODON_INSTANCE_URL`
- `MASTODON_ACCESS_TOKEN`

Example:

```env
MASTODON_INSTANCE_URL=https://mastodon.social
MASTODON_ACCESS_TOKEN=...
```

Titled posts syndicate as the title plus canonical URL. Untitled notes syndicate as native social posts. Photo notes upload attached photos where possible.
