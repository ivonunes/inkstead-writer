# Cloudflare Workers

Inkstead Writer can publish a static site to Cloudflare Workers.

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

You do not need Wrangler installed. Inkstead Writer creates or updates the Worker named by `projectName` and publishes the configured build output.

Routes, custom domains, and workers.dev subdomains are still managed in Cloudflare. Inkstead Writer deploys the Worker script named by `projectName`.
