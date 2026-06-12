# Continuous Integration

CI providers let Inkstead Writer publish your site automatically when you push changes.

During `inkstead-writer init`, choose whether you want Inkstead Writer to create a CI workflow. You can also add or change CI later in `inkstead-writer.json`.

Generated workflows usually:

- check out the repository
- run the site's `./inkstead-writer publish` command
- deploy with the configured publishing target
- run syndication after deployment, when enabled
- save syndication links back to the repository when the platform allows it

The generated `./inkstead-writer` command downloads the Linux Inkstead Writer binary for the version recorded in `inkstead-writer.json` when the runner does not already have it cached.

Use `./inkstead-writer requirements` to see which secrets or variables your selected publishing and syndication providers need. Add those names to your CI provider before expecting automated publishing to work.

Generated workflows forward every supported syndication variable, not just the ones you currently use. Unset secrets are harmless, and it means enabling another syndication provider later only needs the new secret added in CI — the workflow does not need to be regenerated.

When syndication adds links to post frontmatter, Inkstead Writer tries to commit those changes back to the repository. If the CI provider cannot push, syndication can still publish, but those links will not be saved automatically.

Provider guides:

- [GitHub Actions](/ci/github-actions/)
- [GitLab CI](/ci/gitlab-ci/)
- [Forgejo Actions](/ci/forgejo-actions/)
