# Flickr

Inkstead Writer can upload your photo notes to Flickr. Flickr needs the most setup of the supported services, but it is a one-time job: four values, created once, that never expire.

Inkstead Writer reads four environment variables:

| Variable | What it is |
| --- | --- |
| `FLICKR_API_KEY` | Your API key from the Flickr App Garden |
| `FLICKR_API_SECRET` | The secret that comes with the key |
| `FLICKR_ACCESS_TOKEN` | The token that authorises your account |
| `FLICKR_ACCESS_SECRET` | The secret that comes with the token |

Set them in your site's `.env` file for local publishing, or as CI secrets or variables.

## Getting the keys and tokens

First, create an API key at the [Flickr App Garden](https://www.flickr.com/services/apps/create/). A non-commercial key is fine for a personal site. That gives you `FLICKR_API_KEY` and `FLICKR_API_SECRET`.

Then authorise your own account once using Flickr's OAuth flow to obtain `FLICKR_ACCESS_TOKEN` and `FLICKR_ACCESS_SECRET`. Flickr's [authentication documentation](https://www.flickr.com/services/api/auth.oauth.html) describes the flow, and most OAuth 1.0a helper tools can complete it with your API key and secret. Ask for `write` permission. Flickr access tokens do not expire, so you only do this once.

## What gets posted

Flickr receives the first photo from a photo note and uses the note text as the description.

Add `flickr` to a photo note when you want that note to upload to Flickr:

```yaml
syndicate:
  - flickr
```

See [Syndication](index.md) for how results are recorded and how to retry a failure.
