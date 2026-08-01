# GitHub Pages

If your site lives in a GitHub repository, GitHub Pages can host it for free. Publishing runs through GitHub Actions: you push your writing, and a workflow builds and deploys the site for you.

## Configuration

Choose GitHub Pages during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "github-pages"
  }
}
```

GitHub Pages uses GitHub Actions, so Inkstead Writer also generates `.github/workflows/publish.yml` when this target is selected during `init`. The workflow itself is described in [GitHub Actions](../ci/github-actions.md).

## Repository settings

In GitHub, open the repository settings and configure Pages to deploy from GitHub Actions. This is a one-time setting; without it, the workflow builds the site but GitHub does not serve it.

## Publishing

Push to GitHub, or run the generated workflow manually from the Actions tab. The workflow runs `./inkstead-writer publish` and deploys the built site to GitHub Pages.

> **Note:** Deployment happens inside GitHub Actions, so a local `./inkstead-writer deploy` does not publish directly to GitHub Pages.

## Secrets

GitHub Pages itself does not need deployment secrets. If you use syndication, add the provider variables from `.env.example` as GitHub Actions secrets.

If you want to check content, config and any syndication variables before pushing, run `./inkstead-writer doctor` locally.
