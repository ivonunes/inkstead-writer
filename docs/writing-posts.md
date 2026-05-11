# Writing Posts

Posts live in `content/posts` as Markdown files with optional frontmatter.

```md
---
title: A Post Title
date: 2026-05-10T18:30:00+01:00
---

Your post content goes here.
```

To create a post locally with the right filename and frontmatter:

```bash
npx inkstead new post
```

Inkstead asks whether the post is a long article or a note. Articles get a `title` field and an empty body; notes use the text you enter as the body and omit `title`.

If syndication is enabled for the site, new articles and notes include the enabled text-capable providers in `syndicate` by default. Photo-only providers are skipped for text posts.

## Articles, Notes, And Photo Notes

Inkstead infers the kind of post from the content:

- Posts with a `title` are articles.
- Posts without a `title` are notes.
- Untitled posts with images are photo notes.

Inkstead infers photo notes from Markdown or HTML images in the body.

Pages live in `content/pages` and never syndicate.

## Permalinks

Posts use dated permalinks by default:

```txt
/2026/05/10/my-post/
```

That keeps URLs stable even if two posts share similar titles over time.

## Photos

For photo posts, add a Markdown image to an untitled post:

```md
---
date: 2026-05-10T18:30:00+01:00
---

Morning coffee.

![](/media/coffee.jpg)
```

You can keep original files in `content/media` and reference the public path you want your theme to render.

During builds, Inkstead copies `content/media` to `/media/`, resizes very large images to a reasonable web size, and strips metadata from the copied files. Your originals in `content/media` are left unchanged. Passthrough assets are not optimized.

You can tune or disable this in `site.config.ts`:

```ts
export default defineConfig({
  photos: {
    optimize: true,
    maxWidth: 2400,
    maxHeight: 2400,
    quality: 82
  }
});
```

## Categories

Posts can include one or more categories:

```yaml
categories:
  - Photography
  - Travel
```

When categories are present, Inkstead generates paginated category indexes at `/categories/<category>/` and RSS feeds at `/categories/<category>/feed.xml`.

Posts in nested folders under `content/posts` also receive categories from their directory names. For example, `content/posts/essays/my-post.md` is assigned to `Essays` even without category frontmatter. Posts directly inside `content/posts` only use frontmatter categories.

## Pagination

Inkstead paginates the homepage and category indexes automatically. By default, each index page shows 20 posts before creating pages like:

```txt
/page/2/
/categories/photography/page/2/
```

The default theme includes `Newer` and `Older` links when more pages exist.

To change the number of posts per page:

```ts
export default defineConfig({
  pagination: {
    postsPerPage: 10
  }
});
```

## Excerpts

Article index excerpts use `summary` frontmatter when present:

```yaml
summary: A short custom introduction for index pages.
```

Without `summary`, Inkstead uses the content before `<!--more-->`.

```md
This appears on index pages.

<!--more-->

This only appears on the post page.
```

Themes can use `post.excerpt` and `post.hasMore`. `post.excerpt` is rendered HTML, so Markdown links and formatting work on index pages.

If neither `summary` nor `<!--more-->` exists, Inkstead creates a short excerpt from the post body automatically.

## Raw HTML And Line Breaks

Markdown supports raw HTML and hard line breaks by default. That means small HTML snippets are preserved, and single newlines inside a paragraph render as `<br>`.
