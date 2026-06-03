# Cloudflare Workers

Inkstead Writer deploys static sites to Cloudflare Workers through the Cloudflare Workers API.

Choose Cloudflare Workers during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "cloudflare-workers",
    "projectName": "my-website"
  }
}
```

Change `projectName` to the Worker name you want to deploy.

## Required Environment Variables

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`

For local publishing, put those values in `.env`. For automated publishing, add them as CI secrets or variables.

Run `./inkstead-writer doctor` before the first publish to confirm the Cloudflare variables are available.

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

Inkstead Writer uploads the configured build output directory with the Workers static assets direct-upload API, then deploys a small Worker module that serves those assets. You do not need Wrangler installed.

Routes, custom domains, and workers.dev subdomains are still managed in Cloudflare. Inkstead Writer deploys the Worker script named by `projectName`.
