# Forgejo Actions

Forgejo is a self-hosted git service, and Forgejo Actions is its CI. If your site lives on a Forgejo instance, the generated workflow publishes it every time you push, so a finished post goes live on its own.

Inkstead Writer can generate a `.forgejo/workflows/publish.yml` workflow during `inkstead-writer init`. The workflow runs when you push. It checks out the repository and runs:

```bash
./inkstead-writer publish
```

## Setting up secrets

To see which secrets your site needs, run:

```bash
./inkstead-writer requirements
```

Add the listed environment variable names as Forgejo Actions secrets. The exact list depends on your publishing and syndication setup.

## Saving syndication links

When syndication adds links to your posts, the workflow commits them back to the current branch, which requires the checkout credentials to have push permission. See [Saving syndication links](index.md#saving-syndication-links) for how this works.
