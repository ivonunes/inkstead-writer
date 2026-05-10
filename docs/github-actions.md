# GitHub Actions

Generated sites include `.github/workflows/publish.yml` so the site can publish automatically when you push to `main`.

## Set Up Secrets

Run `npm run requirements`, then add the listed environment variable names as GitHub repository secrets. The exact list depends on your deployment and syndication adapters.

## Publishing Order

`inkstead publish` deploys the site before syndication runs, so the links shared to social media are already live. If syndication adds new links to your posts, Inkstead publishes the updated site again.

## Manual Runs

The generated workflow also supports manual runs from the GitHub Actions tab through `workflow_dispatch`.
