# Themes

Inkstead Writer ships with a simple default theme. Add `.plume` files when you want to replace part of it with your own design.

Plume is the template language used by Writer. This page focuses on how Writer loads themes and what data it passes to them. For the language itself, use the [Plume syntax reference](https://inkstead.dev/plume/syntax.html), [component guide](https://inkstead.dev/plume/components.html), [styles and assets guide](https://inkstead.dev/plume/styles-assets.html), and [interactivity guide](https://inkstead.dev/plume/interactivity.html).

## Theme Folder

Create a `theme` folder in your site. The organized layout is the recommended shape and is what `theme eject` writes:

```txt
theme/
  layouts/
    default.plume
  pages/
    home.plume
    category.plume
    post.plume
    page.plume
    feed.xml.plume
    feed.json.plume
  components/
    PostCard.plume
  styles/
    site.css
  scripts/
    site.plume
```

All files are optional. Writer falls back to the built-in template when an override is missing.

## Page Templates

Writer looks for these page templates under `theme/pages`:

- `home.plume` for the homepage.
- `category.plume` for category indexes.
- `post.plume` for posts.
- `page.plume` for standalone pages.
- `feed.xml.plume` for RSS feeds.
- `feed.json.plume` for JSON Feed.

Standalone pages can also use slug-specific templates. For example, `content/pages/photos.md` normally renders with `page.plume`, but if `theme/pages/photos.plume` exists, Writer uses that template for `/photos/`.

```txt
content/pages/photos.md
theme/pages/photos.plume
```

```plume
<h1>{page.title}</h1>

<div class="photo-grid">
  @for post in photoPosts {
    <a href="{post.urlPath}">
      @image(post.firstImage, alt: post.alt | default(""))
    </a>
  }
</div>
```

## Plume In Writer

Writer marks generated content HTML as safe, so `{post.html}`, `{post.excerpt}`, `{page.html}`, and `{content}` render as HTML without `| raw`. Ordinary strings still escape by default.

Use `| raw` only when you intentionally need to render your own trusted string as HTML.

For Plume language details, use:

- [Template syntax](https://inkstead.dev/plume/syntax.html)
- [Components](https://inkstead.dev/plume/components.html)
- [Styles, scripts, and assets](https://inkstead.dev/plume/styles-assets.html)
- [Interactivity](https://inkstead.dev/plume/interactivity.html)

## Theme Commands

Check a theme without building the site:

```bash
./inkstead-writer theme check
```

Format templates:

```bash
./inkstead-writer theme format
./inkstead-writer theme format --check
```

Run the language server for IDE integrations:

```bash
./inkstead-writer theme language-server
```

Writer embeds Plume, so a site-local `./inkstead-writer` wrapper uses the Plume version tied to that site's Writer version. The standalone Plume CLI and IDE extension details live in the [Plume tooling docs](https://inkstead.dev/plume/cli-editor.html).

## Feed Templates

Writer writes RSS at `/feed.xml` and JSON Feed at `/feed.json`.

Override these files to customize them:

```txt
theme/pages/feed.xml.plume
theme/pages/feed.json.plume
```

Both templates receive a `feed` object with:

- `title`
- `description`
- `url`
- `path`
- `items`
- `category`

Category feeds use the same templates with `feed.category` populated and `feed.items` scoped to that category. Category pages also advertise their category RSS and JSON feeds through `meta.feedAlternates`.

RSS browser presentation is opt-in. In `theme/pages/feed.xml.plume`, declare `@style` and `@script` resources, then include `feed.presentationScriptSrc` where you want the XHTML script element to appear:

```plume
@style {
  body {
    font-family: system-ui;
  }
}

@script(language: "javascript") {
  console.log("Feed presentation loaded", window.PlumeFeed.styles);
}

<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>{feed.title}</title>
    @if feed.presentationScriptSrc {
    <script xmlns="http://www.w3.org/1999/xhtml" src="{feed.presentationScriptSrc}"></script>
    }
  </channel>
</rss>
```

RSS readers still receive RSS. The presentation script only runs in browsers that execute XHTML script elements embedded in XML. The built-in feed templates do not include browser presentation by default.

## Assets And Images

Use `asset()` for theme files that should be copied to the built site with a fingerprinted URL:

```plume
<img src="{asset('images/avatar.png')}" alt="Ivo">
```

Relative asset paths are resolved relative to the template or component file first, then relative to the theme folder. Theme assets are emitted under `/assets/plume/`.

For images, prefer `@image`. Writer resolves the asset, fingerprints theme images, adds dimensions when it can read them, and defaults to `loading="lazy"` and `decoding="async"`:

```plume
@image("images/avatar.png", alt: "Ivo", class: "avatar", sizes: "64px")
```

Add `widths:` to generate responsive variants and a `srcset` automatically:

```plume
@image("images/hero.jpg", alt: "Coastal path", widths: [480, 960, 1440], sizes: "(min-width: 960px) 960px, 100vw")
```

Site media references such as `/media/photo.jpg` keep their public media path. Theme-local images and responsive variants are copied to `/assets/plume/`.

## Styles And Scripts

Plume templates can declare styles and scripts next to the markup that uses them. Writer extracts those resources into fingerprinted files under `/assets/plume/` and injects them into the page.

```plume
@style(file: "styles/site.css")
@script(file: "scripts/site.plume")
```

You can also write inline resource blocks:

```plume
@style(scoped) {
  .photo-grid {
    display: grid;
    gap: 1rem;
  }
}

@script {
  let menu = page.query("#menu")

  on ".menu-toggle".click {
    menu.toggleClass("is-open")
  }
}
```

For the full resource model, see [Plume styles, scripts, and assets](https://inkstead.dev/plume/styles-assets.html).

## Interactivity

Writer emits `/assets/plume-runtime.js` only on pages that use Plume state, state bindings, style bindings, browser actions, or enhanced navigation.

```plume
@state expanded = false

<button on:click="{expanded.toggle()}" aria-expanded="{expanded}">
  {expanded ? "Hide" : "Show"} details
</button>

<section hidden?="{!expanded}" class:open="{expanded}">
  {post.excerpt}
</section>
```

Use `@navigation` in `theme/layouts/default.plume` when same-origin links should fetch and swap page content without a full reload:

```plume
@navigation(root: "main", viewTransitions: true, scroll: "top") {
  on:beforeSwap {
    page.addClass("is-leaving")
  }

  on:afterSwap {
    page.removeClass("is-leaving")
  }
}
```

See the [Plume interactivity guide](https://inkstead.dev/plume/interactivity.html) for state, actions, measurement, viewport events, scripts, and navigation hooks.

## Context

Templates receive:

- `site`
- `config`
- `posts`
- `pages`
- `categories`
- `photoPosts`
- `data`, containing configured build-time JSON data sources
- `collections.posts`
- `collections.pages`
- `collections.categories`
- `collections.photoPosts`
- `collections.<name>`, for custom Markdown collections in `content/collections/<name>`
- `pagination` on index/category pages
- `post` on post pages
- `page` on page pages
- `category` on category pages
- `meta`
- `now`, including `now.year`

`meta` includes `title`, `canonicalUrl`, and `description`. Post and page pages use an excerpt of their own content for `meta.description`; index and category pages use `site.description`.

Post objects include `previous` and `next` so themes can add post navigation.

`photoPosts` is intended for photography grids. It includes photo notes whose primary image is not a PNG, so screenshots and other PNG notes do not appear there by default.

Configured data sources are loaded at build time and exposed under `data`:

```json
{
  "data": {
    "events": {
      "url": "https://example.com/events.json",
      "cache": "1h"
    },
    "links": { "file": "data/links.json" }
  }
}
```

```plume
@for event in data.events {
  <article>
    <h2>{event.title}</h2>
    <time datetime="{event.date}">{event.date}</time>
  </article>
}
```

Remote data sources must return JSON. Local file sources are resolved relative to the site root. Use cache durations like `30m`, `1h`, or `1d` for remote sources you do not want to fetch on every build.

## Layouts

If a template returns a full HTML document, Writer uses it as-is. Otherwise, Writer wraps the rendered content in a layout.

Override `theme/layouts/default.plume` to control the document shell.

## Starting From The Default Theme

Copy the default templates into your site:

```bash
./inkstead-writer theme eject
```

Existing files are left alone. Use `--force` if you want to overwrite them.

## Passthrough Assets

Use `asset()`, `@image`, `@style`, and `@script` when you want Writer to copy, fingerprint, and inject theme assets automatically.

For other static files, such as downloads or files you want to reference manually, use asset passthrough:

```json
{
  "assets": {
    "passthrough": [{ "from": "public", "to": "." }]
  }
}
```

For example, `public/assets/site.css` becomes `dist/assets/site.css`.

## Footer Attribution

The default templates include a copyright notice and a small `Powered by Inkstead Writer` link. To remove the attribution without ejecting or editing the default templates, set:

```json
{
  "theme": {
    "showPoweredBy": false
  }
}
```

## Build Hooks

Use hooks when a theme needs generated assets before Writer copies passthrough files or resolves Plume asset references. A common use is bundling larger JavaScript modules or compiling CSS before referencing the output with `@script(file:)` or `@style(file:)`.

```json
{
  "hooks": {
    "beforeBuild": ["./build-theme-assets.sh"]
  },
  "assets": {
    "passthrough": [{ "from": "public", "to": "." }]
  }
}
```

This keeps bundling outside the engine while still making `./inkstead-writer build` produce a complete site.
