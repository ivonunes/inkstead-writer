# Cloudflare Workers

Inkstead deploys static sites to Cloudflare Workers with Wrangler.

Choose Cloudflare Workers during `npx inkstead init`, or add this to `site.config.ts` later:

```ts
deploy: {
  provider: "cloudflare-workers",
  projectName: "my-website"
}
```

Change `projectName` to the Worker name you want to deploy.

## Required Environment Variables

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`

For local publishing, put those values in `.env`. For automated publishing, add them as CI secrets or variables.

## Publish

```bash
npm run publish
```

`npm run publish` builds and deploys the site before running syndication, so links are live before they are posted elsewhere.

If you only want to deploy an already-built site:

```bash
npm run build
npm run deploy
```

Inkstead writes the Wrangler files it needs during deployment, including the Worker entrypoint and asset directory configuration.

If `wrangler.toml` already exists, Inkstead leaves it alone. That lets you customize Wrangler settings such as custom domains, routes, or environment-specific configuration after the first deploy.
