# GitHub Actions

Generated sites include `.github/workflows/publish.yml` so the site can publish automatically when you push to `main`.

The generated workflow checks out the repository and runs `./inkstead-writer publish`. It also supports manual runs from the GitHub Actions tab.

## Set Up Secrets

Run `./inkstead-writer requirements`, then add the listed environment variable names as GitHub repository secrets. The exact list depends on your publishing and syndication setup.

GitHub Pages itself does not need deployment secrets, but syndication providers and other deployment targets usually do.
