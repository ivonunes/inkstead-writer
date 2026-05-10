import type { SyndicationProviderName } from "../config/types.js";

export type PostKind = "article" | "note" | "photo-note";

export interface ParsedMarkdown {
  path: string;
  slug: string;
  frontmatter: Record<string, unknown>;
  body: string;
  html: string;
}

export interface NormalizedPost extends ParsedMarkdown {
  kind: PostKind;
  title?: string;
  summary?: string;
  excerpt: string;
  hasMore: boolean;
  date: Date;
  lastmod?: Date;
  urlPath: string;
  canonicalUrl: string;
  photos: string[];
  sourcePhotos: string[];
  firstImage?: string;
  alt?: string;
  categories: string[];
  syndicate: SyndicationProviderName[];
  syndication: Record<string, Record<string, unknown>>;
  syndicationUrls: string[];
  previous?: NormalizedPost;
  next?: NormalizedPost;
}

export interface CategoryCollection {
  name: string;
  slug: string;
  urlPath: string;
  feedPath: string;
  posts: NormalizedPost[];
}

export interface NormalizedPage extends ParsedMarkdown {
  title: string;
  urlPath: string;
  canonicalUrl: string;
}
