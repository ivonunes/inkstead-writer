# Updating And Migrating

Inkstead Writer sites commit a small root `./inkstead-writer` wrapper. The wrapper reads the version in `inkstead-writer.json` and downloads the matching release into the user Inkstead Writer cache when needed. The same launcher can be installed globally; outside a site it bootstraps `inkstead-writer init` and cache management, and inside a site it runs commands against that site's pinned version.

Each site records the Inkstead Writer site format version in `inkstead-writer.json`. The `migrate` command compares that version with the binary you are running, applies every migration needed between the two versions, refreshes generated workflow files and the wrapper, and then updates the recorded version. Some releases may not need a site migration.

To update a site to the latest Inkstead Writer release:

```bash
./inkstead-writer update
```

For CI or release-check scripts, `./inkstead-writer update --check` reports whether a newer release is available without changing files and exits with a non-zero status when the site is out of date. To preview the exact migration without writing changes, run:

```bash
./inkstead-writer update --dry-run
```

To inspect or prune downloaded binaries:

```bash
./inkstead-writer cache list
./inkstead-writer cache clean --dry-run
./inkstead-writer cache clean
```

The cache defaults to `~/Library/Caches/inkstead-writer` on macOS and `${XDG_CACHE_HOME:-$HOME/.cache}/inkstead-writer` on Linux. Set `INKSTEAD_WRITER_CACHE_DIR` to use a different location.

To apply migrations for the version already recorded in the site:

```bash
./inkstead-writer migrate
```

Then run:

```bash
./inkstead-writer doctor
./inkstead-writer build
```

If you use custom templates, check your theme against the current [Themes](/themes/) context values after major upgrades.

If Inkstead Writer reports a manual migration, finish that change and run `./inkstead-writer migrate` again. The recorded version is not advanced while a required manual step is still outstanding.
