# Continuous Integration

CI adapters let Inkstead publish your site automatically when you push changes.

During `npx inkstead init`, choose whether you want Inkstead to create a CI workflow. You can also add or change CI later in `site.config.ts`.

Generated CI workflows usually:

- install dependencies
- build the site
- deploy it with the configured deployment adapter
- run syndication after deployment, when enabled
- save syndication metadata back to the repository when the platform allows it

Use `npm run requirements` to see which secrets or variables your selected adapters need. Add those names to your CI provider before expecting automated publishing to work.

Adapter guides:

- [GitHub Actions](/github-actions/)
- [GitLab CI](/gitlab-ci/)
