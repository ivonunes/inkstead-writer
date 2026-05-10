# Obsidian

[Inkstead Writer](https://github.com/ivonunes/inkstead-writer) is the companion Obsidian plugin for writing Inkstead posts and pages from a vault.

Your site repository remains the canonical copy. Obsidian is a writing and publishing client.

Suggested vault layout:

```txt
Website/posts
Website/pages
Website/photos
```

These map to `content/posts`, `content/pages`, and `content/photos` in the site repository.

Useful commands:

- `Inkstead: New post`
- `Inkstead: New page`
- `Inkstead: Publish current file`
- `Inkstead: Pull remote updates`
- `Inkstead: Validate current file`

Sync behavior:

- Local drafts win before publishing.
- Remote published versions win for syndication metadata when the local file has not changed.
- If local and remote both changed, Inkstead reports a conflict instead of merging silently.

Install the plugin from the Inkstead Writer project by building it:

```bash
npm run build
```

That creates:

```txt
dist/
  main.js
  manifest.json
  styles.css
```

Copy or symlink `dist` to `.obsidian/plugins/inkstead-writer` in a vault, then enable Inkstead Writer in Obsidian community plugin settings.
