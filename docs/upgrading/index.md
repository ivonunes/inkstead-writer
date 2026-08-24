# Upgrading

Every Inkstead Writer release gets a page here. It lists whatever the release
needs from your site, with the fix for each: a changed command, a changed
configuration key, an edit only you can make. A release that needs nothing
says so.

## Updating a site

Inkstead Writer sites commit a small root `./inkstead-writer` command. It reads the version in `inkstead-writer.json` and downloads the matching release when needed. That keeps each site on the Writer version it records.

The globally installed `inkstead-writer` command is mainly for creating sites and managing cached binaries. Inside a site, use `./inkstead-writer`.

To update a site to the latest Inkstead Writer release:

```bash
./inkstead-writer update
```

For CI or release-check scripts, `./inkstead-writer update --check` reports whether a newer release is available without changing files and exits with a non-zero status when the site is out of date. To preview the exact migration without writing changes, run:

```bash
./inkstead-writer update --dry-run
```

## Migrations

The `migrate` command compares the version recorded in `inkstead-writer.json` with the binary you are running. It applies needed migrations, refreshes generated workflow files and the site command, then updates the recorded version. Some releases do not need a site migration.

To apply migrations for the version already recorded in the site:

```bash
./inkstead-writer migrate
```

Then run:

```bash
./inkstead-writer doctor
./inkstead-writer build
```

If you use custom templates, check your theme against the current [Themes](/start/themes/) context values after major upgrades.

If Inkstead Writer reports a manual migration, finish that change and run `./inkstead-writer migrate` again. The recorded version is not advanced while a required manual step is still outstanding.

## The binary cache

To inspect or prune downloaded binaries:

```bash
./inkstead-writer cache list
./inkstead-writer cache clean --dry-run
./inkstead-writer cache clean
```

The cache defaults to `~/Library/Caches/inkstead-writer` on macOS and `${XDG_CACHE_HOME:-$HOME/.cache}/inkstead-writer` on Linux. Set `INKSTEAD_WRITER_CACHE_DIR` to use a different location.

## Versions

<!-- newest-first: prepare-release.sh inserts each release's line below -->
- [Inkstead Writer 2.3.1](/upgrading/2.3.1/)
- [Inkstead Writer 2.3.0](/upgrading/2.3.0/)
- [Inkstead Writer 2.2.1](/upgrading/2.2.1/)
