# Site Configuration

Most site settings live in one file, `inkstead-writer.json`, at the root of your site. `inkstead-writer init` creates a working file for you, and you edit it as your site grows. This page walks through each section of the file.

In this guide you will learn:

- where your site's title, author and timezone live
- how to change the content folders and build output
- how to adjust URLs, Markdown, feeds and media handling
- how to point Inkstead Writer at a custom theme and external data

After changing configuration, check that everything still fits together:

```bash
./inkstead-writer doctor
```

`doctor` reports anything the change broke; see [what doctor checks](commands.md#what-doctor-checks) for the full list.

The file starts with a `$schema` key pointing at `https://inkstead.app/writer/schema/inkstead-writer.json`. Editors that understand JSON Schema use it to check the file and suggest keys as you type. `init` writes it for you, and `migrate` adds it to older sites.

## Site details

The `site` section controls the public identity of the website:

```json
{
  "site": {
    "title": "My Website",
    "url": "https://example.com",
    "author": "Your Name",
    "description": "Notes, photos and longer writing."
  }
}
```

Optional fields include `lang`, `timezone`, `email`, `avatar`, `bio`, `navigation` and `social`. Themes can use these values when rendering headers, feeds, author details and social links.

`timezone` takes an IANA identifier such as `Europe/Lisbon`. Post timestamps written with an explicit offset, such as `2026-05-10T18:30:00+01:00`, are honoured as written; timestamps without an offset and date-only values are interpreted as UTC. The timezone then determines which calendar day each post falls on for dated post URLs and displayed dates. When unset, UTC is used.

> **Warning:** Dated URLs depend on the timezone, so changing `timezone` later can move the permalink of any post published near midnight.

## Content folders

Inkstead Writer looks for your writing in these folders by default:

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

Posts, pages, media and collections can live somewhere else if you change those paths. The docs use the default paths unless a section says otherwise.

Site media is published at `/media/` regardless of where the source media folder lives. For example, a file at `content/media/photo.jpg` is referenced as `/media/photo.jpg` in posts and templates.

## Build output

By default, builds are written to `dist`:

```json
{
  "build": {
    "output": "dist"
  }
}
```

If you change the output directory, run `./inkstead-writer migrate` or update generated CI files so they publish the same folder.

## URLs, Markdown and feeds

Posts use dated URLs by default:

```txt
/2026/05/10/my-post/
```

If you prefer URLs without the date, switch to slug-only post URLs:

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

During builds, Inkstead Writer keeps your original files unchanged and optimises the copied output:

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

## Themes and assets

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

See [Themes](themes.md) for template, asset and hook details.

## Data sources

If a page needs data from outside the site, such as an events list or a set of links, templates can receive build-time JSON data:

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

Remote data sources must return JSON. Local files are resolved relative to the site root. Use cache durations like `30m`, `1h` or `1d` when remote data does not need to be fetched on every build.

## Publishing and app setup

Publishing, CI, syndication and app connection settings also live in `inkstead-writer.json`, but their setup depends on the provider:

- [Deployment](../deployment/index.md)
- [Continuous Integration](../ci/index.md)
- [Syndication](../syndication/index.md)
- [App Connection](../extras/app-connection.md)
