# GitHub Actions

Generated sites include `.github/workflows/publish.yml` so the site can publish automatically when you push to `main`.

The generated workflow checks out the repository and runs `./inkstead-writer publish`. The committed wrapper downloads the Linux Inkstead Writer binary for the version recorded in `inkstead-writer.json` when it is not already cached.

## Set Up Secrets

Run `./inkstead-writer requirements`, then add the listed environment variable names as GitHub repository secrets. The exact list depends on your deployment and syndication adapters.

## Publishing Order

`./inkstead-writer publish` deploys the site before syndication runs, so the links shared to social media are already live. If syndication adds new links to your posts, Inkstead Writer publishes the updated site again.

## Manual Runs

The generated workflow also supports manual runs from the GitHub Actions tab through `workflow_dispatch`.
