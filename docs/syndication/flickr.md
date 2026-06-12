# Flickr

Inkstead Writer can syndicate photo notes to Flickr.

Required environment variables:

- `FLICKR_API_KEY`
- `FLICKR_API_SECRET`
- `FLICKR_ACCESS_TOKEN`
- `FLICKR_ACCESS_SECRET`

## Get The Keys And Tokens

Flickr needs the most setup of the supported services, but it is a one-time job.

First, create an API key at the [Flickr App Garden](https://www.flickr.com/services/apps/create/). A non-commercial key is fine for a personal site. That gives you `FLICKR_API_KEY` and `FLICKR_API_SECRET`.

Then authorise your own account once using Flickr's OAuth flow to obtain `FLICKR_ACCESS_TOKEN` and `FLICKR_ACCESS_SECRET`. Flickr's [authentication documentation](https://www.flickr.com/services/api/auth.oauth.html) describes the flow, and most OAuth 1.0a helper tools can complete it with your API key and secret. Ask for `write` permission. Flickr access tokens do not expire, so you only do this once.

## What Gets Posted

Flickr receives the first photo from a photo note and uses the note text as the description.

Add `flickr` to a photo note when you want that note to upload to Flickr:

```yaml
syndicate:
  - flickr
```
