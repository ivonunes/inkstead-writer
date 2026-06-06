# Forgejo Actions

Inkstead Writer can generate a `.forgejo/workflows/publish.yml` workflow during `inkstead-writer init`.

The workflow runs on `main` and can also be started manually from Forgejo. It checks out the repository and runs:

```bash
./inkstead-writer publish
```

## Secrets

Run `./inkstead-writer requirements`, then add the listed environment variable names as Forgejo Actions secrets. The exact list depends on your publishing and syndication setup.

## Syndication Metadata Commits

When syndication adds links to your posts in Forgejo Actions, Inkstead Writer commits those changes with `[skip ci]` and pushes them back to the current branch.

Your Forgejo runner must have permission to push through the checkout credentials. If it does not, syndication can still publish, but the metadata commit will not be pushed back automatically.
