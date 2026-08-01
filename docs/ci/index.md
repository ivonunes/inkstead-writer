# Continuous Integration

Continuous integration, CI for short, is a service in your git host that runs commands whenever you push. With CI set up, you push a new post and your provider builds, deploys and syndicates the site for you. Nothing needs to run on your own machine.

During `inkstead-writer init`, choose whether you want Inkstead Writer to create a CI workflow. You can also add or change CI later in `inkstead-writer.json`.

## What a generated workflow does

Generated workflows usually:

- check out the repository
- run the site's `./inkstead-writer publish` command
- deploy with the configured publishing target
- run syndication after deployment, when enabled
- save syndication links back to the repository when the platform allows it

The `./inkstead-writer` wrapper downloads and caches the Inkstead Writer binary for the version recorded in `inkstead-writer.json`, so every run uses the version your site expects; see [the `./inkstead-writer` wrapper](../start/commands.md#the-inkstead-writer-wrapper) for how it works.

## Secrets and variables

Your publishing and syndication providers need access tokens, and CI needs to know them. To see which names your site requires, run:

```bash
./inkstead-writer requirements
```

It lists the secrets or variables your selected publishing and syndication providers need. Add those names to your CI provider before expecting automated publishing to work.

Generated workflows forward every supported syndication variable, not just the ones you currently use. Unset secrets are harmless, and it means enabling another syndication provider later only needs the new secret added in CI. The workflow does not need to be regenerated.

## Saving syndication links

When syndication adds links to post frontmatter, Inkstead Writer commits those changes back to the repository so your posts keep their record of where they went. The commit message carries `[skip ci]`, which stops that push from starting another CI run.

The CI provider must be allowed to push for this to work. If it cannot push, syndication still publishes, but those links will not be saved automatically. Each provider guide notes what its platform needs.

## Provider guides

Each guide covers one CI provider:

- [GitHub Actions](github-actions.md)
- [GitLab CI](gitlab-ci.md)
- [Forgejo Actions](forgejo-actions.md)
