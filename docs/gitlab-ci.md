# GitLab CI

Inkstead can generate a `.gitlab-ci.yml` pipeline during `npx inkstead init`.

The pipeline runs on `main` and can also be started manually from GitLab. It installs dependencies and runs:

```bash
npm run publish
```

If you choose [GitLab Pages](/deployment/gitlab-pages/) as the deployment adapter, Inkstead generates a Pages-specific pipeline instead.

## CI/CD Variables

Run `npm run requirements`, then add the listed environment variable names as GitLab CI/CD variables. The exact list depends on your deployment and syndication adapters.

## Publishing Order

`inkstead publish` deploys the site before syndication runs, so the links shared to social media are already live. If syndication adds new links to your posts, Inkstead publishes the updated site again.

## Syndication Metadata Commits

When syndication adds links to your posts in GitLab CI, Inkstead commits those changes with `[skip ci]` and pushes them back to the repository.

GitLab must allow the pipeline token to push to the repository. If your project does not allow that, syndication can still publish, but the metadata commit will not be pushed back automatically.
