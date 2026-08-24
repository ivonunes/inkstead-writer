# Unreleased

<!-- unreleased-intro-start (support/prepare-release.sh drops this block at release) -->
The notes for the next release: everything below is in `main` and ships
together when the version is tagged.
<!-- unreleased-intro-end -->

## Editor support for the site configuration

`inkstead-writer.json` now has a published JSON Schema at `https://inkstead.app/writer/schema/inkstead-writer.json`. New sites start with a `$schema` key pointing at it, and editors that understand JSON Schema (VS Code and most others) use it to flag mistakes and suggest keys as you type. See [site configuration](/start/site-configuration/).

Nothing needs to change by hand: `migrate` adds the `$schema` key to an existing site, and a file without it keeps working as before.
