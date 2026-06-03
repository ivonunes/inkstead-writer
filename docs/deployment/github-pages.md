# GitHub Pages

Inkstead Writer publishes GitHub Pages sites through GitHub Actions.

Choose GitHub Pages during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "github-pages"
  }
}
```

GitHub Pages uses GitHub Actions, so Inkstead Writer also generates `.github/workflows/publish.yml` when this adapter is selected during `init`.

## Repository Settings

In GitHub, open the repository settings and configure Pages to deploy from GitHub Actions.

## Publishing

The generated workflow:

- runs `./inkstead-writer publish`
- deploys the built site to GitHub Pages

Local `./inkstead-writer deploy` does not publish directly to GitHub Pages. Push to GitHub, or run the workflow manually from the Actions tab.

## Syndication Order

If syndication is enabled, the workflow publishes the site first, then syndicates posts, saves the new links, rebuilds, and publishes the updated site again.

## Variables

GitHub Pages itself does not need deployment secrets. If you use syndication, add the provider variables from `.env.example` as GitHub Actions secrets.

Run `./inkstead-writer doctor` locally if you want to check content, config, and any syndication variables before pushing.
