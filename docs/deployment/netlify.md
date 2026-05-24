# Netlify

Inkstead deploys static sites to Netlify with the Netlify CLI.

Choose Netlify during `npx inkstead init`, or add this to `site.config.ts` later:

```ts
deploy: {
  provider: "netlify"
}
```

## Required Environment Variables

- `NETLIFY_SITE_ID`
- `NETLIFY_AUTH_TOKEN`

For local publishing, put those values in `.env`. For automated publishing, add them as CI secrets or variables.

`NETLIFY_SITE_ID` is the project ID shown in Netlify project settings. `NETLIFY_AUTH_TOKEN` is a Netlify personal access token.

Run `npm run doctor` before the first publish to confirm the Netlify variables are available.

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

Inkstead deploys the configured build output directory to production with `netlify deploy --prod --no-build`.
