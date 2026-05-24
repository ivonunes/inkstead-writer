# Forgejo Actions

Inkstead can generate a `.forgejo/workflows/publish.yml` workflow during `npx inkstead init`.

The workflow runs on `main` and can also be started manually from Forgejo. It uses a Node 22 container, checks out the repository, installs dependencies, and runs:

```bash
npm run publish
```

## Secrets

Run `npm run requirements`, then add the listed environment variable names as Forgejo Actions secrets. The exact list depends on your deployment and syndication adapters.

## Publishing Order

`inkstead publish` deploys the site before syndication runs, so the links shared to social media are already live. If syndication adds new links to your posts, Inkstead publishes the updated site again.

## Syndication Metadata Commits

When syndication adds links to your posts in Forgejo Actions, Inkstead commits those changes with `[skip ci]` and pushes them back to the current branch.

Your Forgejo runner must have permission to push through the checkout credentials. If it does not, syndication can still publish, but the metadata commit will not be pushed back automatically.
