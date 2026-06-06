# Netlify

Inkstead Writer can publish a static site to Netlify.

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

You do not need the Netlify CLI installed. Inkstead Writer publishes the configured build output directly to the Netlify site identified by `NETLIFY_SITE_ID`.
