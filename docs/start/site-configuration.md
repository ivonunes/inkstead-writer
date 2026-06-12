# Site Configuration

Most site settings live in `inkstead-writer.json`. `inkstead-writer init` creates a working file for you, and you can edit it later as your site grows.

Run this after changing configuration:

```bash
./inkstead-writer doctor
```

Doctor checks that the site can be loaded, required folders exist, publishing settings match the selected provider, and needed environment variables are available.

## Site Details

The `site` section controls the public identity of the website:

```json
{
  "site": {
    "title": "My Website",
    "url": "https://example.com",
    "author": "Your Name",
    "description": "Notes, photos, and longer writing."
  }
}
```

Optional fields include `lang`, `timezone`, `email`, `avatar`, `bio`, `navigation`, and `social`. Themes can use these values when rendering headers, feeds, author details, and social links.

`timezone` takes an IANA identifier such as `Europe/Lisbon`. Post timestamps written with an explicit offset, such as `2026-05-10T18:30:00+01:00`, are honoured as written; timestamps without an offset and date-only values are interpreted as UTC. The timezone then determines which calendar day each post falls on for dated post URLs and displayed dates. When unset, UTC is used. Because dated URLs depend on it, changing `timezone` later can move the permalink of any post published near midnight.

## Content Folders

Inkstead Writer uses these folders by default:

```json
{
  "content": {
    "posts": "content/posts",
    "pages": "content/pages",
    "media": "content/media",
    "collections": "content/collections"
  }
}
```

Posts, pages, media, and collections can live somewhere else if you change those paths. The docs use the default paths unless a section says otherwise.

Site media is published at `/media/` regardless of where the source media folder lives. For example, a file at `content/media/photo.jpg` is referenced as `/media/photo.jpg` in posts and templates.

## Build Output

By default, builds are written to `dist`:

```json
{
  "build": {
    "output": "dist"
  }
}
```

If you change the output directory, run `./inkstead-writer migrate` or update generated CI files so they publish the same folder.

## URLs, Markdown, And Feeds

Posts use dated URLs by default:

```txt
/2026/05/10/my-post/
```

You can switch to slug-only post URLs:

```json
{
  "urls": {
    "posts": "slug"
  }
}
```

Markdown allows raw HTML and hard line breaks by default. You can change that with:

```json
{
  "markdown": {
    "html": true,
    "breaks": true
  }
}
```

Homepage and category pagination defaults to 20 posts per page:

```json
{
  "pagination": {
    "postsPerPage": 10
  }
}
```

Feeds can also be limited:

```json
{
  "feeds": {
    "limit": 20
  }
}
```

## Media

Inkstead Writer keeps your original files unchanged and optimises the copied output during builds:

```json
{
  "media": {
    "optimize": true,
    "maxWidth": 2400,
    "maxHeight": 2400,
    "quality": 82
  }
}
```

Set `optimize` to `false` if you want media copied without resizing or recompression.

## Themes And Assets

The default theme is built in. To use a custom theme folder:

```json
{
  "theme": {
    "path": "theme",
    "showPoweredBy": true
  }
}
```

For static files that should be copied without Plume processing, use passthrough assets:

```json
{
  "assets": {
    "passthrough": [{ "from": "public", "to": "." }]
  }
}
```

For generated theme assets, use build hooks:

```json
{
  "hooks": {
    "beforeBuild": ["./build-theme-assets.sh"],
    "afterBuild": ["./check-built-site.sh"]
  }
}
```

See [Themes](/start/themes/) for template, asset, and hook details.

## Data Sources

Templates can receive build-time JSON data:

```json
{
  "data": {
    "events": {
      "url": "https://example.com/events.json",
      "cache": "1h"
    },
    "links": {
      "file": "data/links.json"
    }
  }
}
```

Remote data sources must return JSON. Local files are resolved relative to the site root. Use cache durations like `30m`, `1h`, or `1d` when remote data does not need to be fetched on every build.

## Publishing And App Setup

Publishing, CI, syndication, and app connection settings also live in `inkstead-writer.json`, but their setup depends on the provider:

- [Deployment](/deployment/)
- [Continuous Integration](/ci/)
- [Syndication](/syndication/)
- [App Connection](/extras/app-connection/)
