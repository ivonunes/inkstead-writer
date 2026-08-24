# Unreleased

<!-- unreleased-intro-start (support/prepare-release.sh drops this block at release) -->
The notes for the next release: everything below is in `main` and ships
together when the version is tagged.
<!-- unreleased-intro-end -->

## Buffer syndication fix

Syndicating through Buffer could fail with an error mentioning `$organizationId`: Inkstead Writer was asking Buffer's API for the channel list in a form it doesn't accept. It now asks in the form Buffer expects.

An expired Buffer key also fails with a message that says what to do (create a new key and reconnect Buffer in Inkstead, or update the `BUFFER_API_KEY` secret) instead of a raw API error. Buffer keys last a year at most, so this is worth knowing about.

Nothing needs to change in an existing site: updating is the fix.

## Editor support for the site configuration

`inkstead-writer.json` now has a published JSON Schema at `https://inkstead.app/writer/schema/inkstead-writer.json`. New sites start with a `$schema` key pointing at it, and editors that understand JSON Schema (VS Code and most others) use it to flag mistakes and suggest keys as you type. See [site configuration](/start/site-configuration/).

Nothing needs to change by hand: `migrate` adds the `$schema` key to an existing site, and a file without it keeps working as before.
