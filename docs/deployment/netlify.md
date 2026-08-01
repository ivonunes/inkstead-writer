# Netlify

Netlify is a hosting service for static sites. Inkstead Writer publishes to it directly through the Netlify API, so there is no extra tooling to install. You need a Netlify account with a site created in it, and two values from that account.

## Configuration

Choose Netlify during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "netlify"
  }
}
```

## Environment variables

Deploying needs two values from your Netlify account:

| Variable | What it is |
| --- | --- |
| `NETLIFY_SITE_ID` | The project ID shown in Netlify project settings. |
| `NETLIFY_AUTH_TOKEN` | A Netlify personal access token. |

For local publishing, put those values in `.env`. For automated publishing, add them as CI secrets or variables.

Before the first publish, confirm the Netlify variables are available:

```bash
./inkstead-writer doctor
```

## Publishing

With the variables in place, publish the site:

```bash
./inkstead-writer publish
```

You do not need the Netlify CLI installed. Inkstead Writer publishes the configured build output directly to the Netlify site identified by `NETLIFY_SITE_ID`.
