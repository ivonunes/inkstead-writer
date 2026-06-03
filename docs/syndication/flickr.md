# Flickr

Inkstead Writer can syndicate photo notes to Flickr.

Required environment variables:

- `FLICKR_API_KEY`
- `FLICKR_API_SECRET`
- `FLICKR_ACCESS_TOKEN`
- `FLICKR_ACCESS_SECRET`

Flickr receives the first photo from a photo note and uses the note text as the description.

Add `flickr` to a photo note when you want that note to upload to Flickr:

```yaml
syndicate:
  - flickr
```
