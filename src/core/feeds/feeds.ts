import type { InksteadConfig } from "../config/types.js";
import type { NormalizedPost } from "../content/types.js";

function xml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function text(value: string): string {
  return value.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

export function rssFeed(config: InksteadConfig, posts: NormalizedPost[], options: { title?: string; path?: string } = {}): string {
  const limit = config.feeds?.limit ?? 25;
  const description = config.site.description ?? config.site.title;
  const feedPath = options.path ?? "/feed.xml";
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom"><channel><title>${xml(options.title ?? config.site.title)}</title><link>${xml(config.site.url)}</link><description>${xml(description)}</description><atom:link href="${xml(config.site.url.replace(/\/$/, ""))}${xml(feedPath)}" rel="self" type="application/rss+xml"/>
${posts.slice(0, limit).map((post) => `<item>${post.title ? `<title>${xml(post.title)}</title>` : ""}<link>${xml(post.canonicalUrl)}</link><guid>${xml(post.canonicalUrl)}</guid><pubDate>${post.date.toUTCString()}</pubDate><description><![CDATA[${post.html}]]></description><content:encoded><![CDATA[${post.html}]]></content:encoded></item>`).join("\n")}
</channel></rss>
`;
}

export function jsonFeed(config: InksteadConfig, posts: NormalizedPost[]): string {
  const limit = config.feeds?.limit ?? 25;
  return JSON.stringify({
    version: "https://jsonfeed.org/version/1.1",
    title: config.site.title,
    home_page_url: `${config.site.url.replace(/\/$/, "")}/`,
    feed_url: `${config.site.url.replace(/\/$/, "")}/feed.json`,
    description: config.site.description,
    authors: [{ name: config.site.author, url: `${config.site.url.replace(/\/$/, "")}/` }],
    items: posts.slice(0, limit).map((post) => ({
      id: post.canonicalUrl,
      url: post.canonicalUrl,
      title: post.title,
      content_html: post.html,
      content_text: text(post.html),
      date_published: post.date.toISOString(),
      date_modified: (post.lastmod ?? post.date).toISOString()
    }))
  }, null, 2);
}

export function sitemap(config: InksteadConfig, urls: string[]): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((url) => `<url><loc>${xml(url)}</loc></url>`).join("\n")}
</urlset>
`;
}
