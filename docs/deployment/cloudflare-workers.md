# Cloudflare Workers

Cloudflare Workers hosts your site on Cloudflare's global network. Inkstead Writer publishes to it directly through the Cloudflare API, so there is no extra tooling to install. You need a Cloudflare account and two values from it, described below.

## Configuration

Choose Cloudflare Workers during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "cloudflare-workers",
    "projectName": "my-website"
  }
}
```

Change `projectName` to the Worker name you want to deploy. A Worker is what Cloudflare calls a deployed project; your site lives inside one.

## Environment variables

Deploying needs two values from your Cloudflare account:

| Variable | What it is |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID. |
| `CLOUDFLARE_API_TOKEN` | A Cloudflare API token with Workers write access. |

For local publishing, put those values in `.env`. For automated publishing, add them as CI secrets or variables.

Before the first publish, confirm the Cloudflare variables are available:

```bash
./inkstead-writer doctor
```

## Publishing

With the variables in place, publish the site:

```bash
./inkstead-writer publish
```

You do not need Wrangler, Cloudflare's own command line tool, installed. Inkstead Writer creates or updates the Worker named by `projectName` and publishes the configured build output to it.

Pointing your own domain at the site happens in the Cloudflare dashboard, not in Inkstead Writer. The same goes for routes and workers.dev subdomains. Inkstead Writer deploys the Worker named by `projectName` and nothing else.
