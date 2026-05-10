# Themes

Inkstead ships with plain default templates, and you can replace them with Liquid templates when you want a custom design.

Create a `theme` folder in your site:

```txt
theme/
  layout.liquid
  home.liquid
  category.liquid
  post.liquid
  page.liquid
```

All files are optional. Inkstead falls back to its built-in template when an override is missing.

Pages can also use slug-specific templates. For example, `content/pages/photos.md` normally renders with `page.liquid`, but if `theme/photos.liquid` exists, Inkstead uses that template for `/photos/` instead. This works for any page slug.

That makes a dedicated photos page straightforward:

```txt
content/pages/photos.md
theme/photos.liquid
```

```liquid
<h1>{{ page.title }}</h1>
<div class="photo-grid">
  {% for post in photoPosts %}
    <a href="{{ post.urlPath }}">
      <img src="{{ post.firstImage }}" alt="{{ post.alt | default: "" | escape }}">
    </a>
  {% endfor %}
</div>
```

To copy the default templates into your site as a starting point, run:

```bash
npx inkstead theme eject
```

Existing files are left alone. Use `--force` if you want to overwrite them.

## Assets

Put CSS, JavaScript, images, and font files wherever you like in your site, then copy them into the built output with asset passthrough:

```ts
export default defineConfig({
  assets: {
    passthrough: [{ from: "public", to: "." }]
  }
});
```

For example, `public/assets/site.css` becomes `dist/assets/site.css`.

## Footer Attribution

The default templates include a copyright notice and a small `Powered by Inkstead` link. If you want to remove the Inkstead attribution without ejecting or editing the default templates, set:

```ts
export default defineConfig({
  theme: {
    showPoweredBy: false
  }
});
```

## Context

Templates receive:

- `site`
- `config`
- `posts`
- `pages`
- `categories`
- `photoPosts`
- `collections.posts`
- `collections.pages`
- `collections.categories`
- `collections.photoPosts`
- `pagination` on index/category pages
- `post` on post pages
- `page` on page pages
- `category` on category pages
- `meta`
- `now`, including `now.year`

Post objects include `previous` and `next` so themes can add post navigation without the default templates rendering it.

`photoPosts` is intended for building a photography-style grid. It includes photo notes whose primary image is not a PNG, so screenshots and other PNG notes do not appear there by default.

## Layout

If a template returns a full HTML document, Inkstead uses it as-is. Otherwise, Inkstead wraps the rendered content in `layout.liquid`.

Override `theme/layout.liquid` to control the document shell.

## Build Hooks

Use hooks when a theme needs generated assets before Inkstead copies passthrough files. A common use is bundling client JavaScript or compiling CSS.

```ts
export default defineConfig({
  hooks: {
    beforeBuild: ["npm run build:js"]
  },
  assets: {
    passthrough: [{ from: "public", to: "." }]
  }
});
```

This keeps JavaScript bundling outside the engine while still making commands like `inkstead build` produce a complete site.
