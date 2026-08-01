# GitHub Actions

GitHub Actions is GitHub's built-in CI service. If your site lives on GitHub, the generated workflow publishes it every time you push, so a finished post goes live on its own.

Generated sites include `.github/workflows/publish.yml`, which runs when you push to `main`. The workflow checks out the repository and runs `./inkstead-writer publish`. It also supports manual runs from the GitHub Actions tab.

If the site deploys to GitHub Pages, see [GitHub Pages](../deployment/github-pages.md) for the repository settings that pair with this workflow.

## Setting up secrets

To see which secrets your site needs, run:

```bash
./inkstead-writer requirements
```

Add the listed environment variable names as GitHub repository secrets. The exact list depends on your publishing and syndication setup.

GitHub Pages itself does not need deployment secrets, but syndication providers and other publishing targets usually do.

## Saving syndication links

When syndication adds links to your posts, the workflow commits them back to the repository as `github-actions[bot]`. See [Saving syndication links](index.md#saving-syndication-links) for how this works.
