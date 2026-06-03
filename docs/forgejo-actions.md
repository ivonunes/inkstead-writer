# Forgejo Actions

Inkstead Writer can generate a `.forgejo/workflows/publish.yml` workflow during `inkstead-writer init`.

The workflow runs on `main` and can also be started manually from Forgejo. It checks out the repository, installs `curl` and `tar` for the wrapper, and runs:

```bash
./inkstead-writer publish
```

The committed wrapper downloads the Linux Inkstead Writer binary for the version recorded in `inkstead-writer.json` when it is not already cached.

## Secrets

Run `./inkstead-writer requirements`, then add the listed environment variable names as Forgejo Actions secrets. The exact list depends on your deployment and syndication adapters.

## Publishing Order

`./inkstead-writer publish` deploys the site before syndication runs, so the links shared to social media are already live. If syndication adds new links to your posts, Inkstead Writer publishes the updated site again.

## Syndication Metadata Commits

When syndication adds links to your posts in Forgejo Actions, Inkstead Writer commits those changes with `[skip ci]` and pushes them back to the current branch.

Your Forgejo runner must have permission to push through the checkout credentials. If it does not, syndication can still publish, but the metadata commit will not be pushed back automatically.
