# GitHub Pages

Inkstead publishes GitHub Pages sites through GitHub Actions.

Choose GitHub Pages during `npx inkstead init`, or add this to `site.config.ts` later:

```ts
deploy: {
  provider: "github-pages"
}
```

GitHub Pages uses GitHub Actions, so Inkstead also generates `.github/workflows/publish.yml` when this adapter is selected during `init`.

## Repository Settings

In GitHub, open the repository settings and configure Pages to deploy from GitHub Actions.

## Publishing

The generated workflow:

- installs dependencies
- runs `npm run build`
- deploys the built site to GitHub Pages

Local `npm run deploy` does not publish directly to GitHub Pages. Push to GitHub, or run the workflow manually from the Actions tab.

## Syndication Order

If syndication is enabled, the workflow publishes the site first, then syndicates posts, saves the new links, rebuilds, and publishes the updated site again.

## Variables

GitHub Pages itself does not need deployment secrets. If you use syndication, add the provider variables from `.env.example` as GitHub Actions secrets.
