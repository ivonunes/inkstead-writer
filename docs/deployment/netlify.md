# Netlify

Inkstead Writer deploys static sites to Netlify through the Netlify API.

Choose Netlify during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "netlify"
  }
}
```

## Required Environment Variables

- `NETLIFY_SITE_ID`
- `NETLIFY_AUTH_TOKEN`

For local publishing, put those values in `.env`. For automated publishing, add them as CI secrets or variables.

`NETLIFY_SITE_ID` is the project ID shown in Netlify project settings. `NETLIFY_AUTH_TOKEN` is a Netlify personal access token.

Run `./inkstead-writer doctor` before the first publish to confirm the Netlify variables are available.

## Publish

```bash
./inkstead-writer publish
```

`./inkstead-writer publish` builds and deploys the site before running syndication, so links are live before they are posted elsewhere.

If you only want to deploy an already-built site:

```bash
./inkstead-writer build
./inkstead-writer deploy
```

Inkstead Writer packages the configured build output directory as a ZIP archive and uploads it directly to the Netlify deploy API. You do not need the Netlify CLI installed.
