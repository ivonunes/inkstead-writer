import { postDateSortValue, type PostFile, type PostSummary } from "./posts.js";

export const postSummaryCacheMaxAge = 5 * 60 * 1000;
export const postFileCacheMaxAge = 5 * 60 * 1000;

export interface CachedPostFile {
  post: PostFile;
  loadedAt: number;
}

export function sortPostSummaries(posts: PostSummary[]): PostSummary[] {
  return [...posts].sort((a, b) => postDateSortValue(b).localeCompare(postDateSortValue(a)));
}

export function isCacheStale(loadedAt: number | undefined, now = Date.now(), maxAge = postSummaryCacheMaxAge): boolean {
  return loadedAt === undefined || now - loadedAt >= maxAge;
}

export function isPostSummaryCacheStale(loadedAt: number | undefined, now = Date.now(), maxAge = postSummaryCacheMaxAge): boolean {
  return isCacheStale(loadedAt, now, maxAge);
}

export function isPostFileCacheStale(cached: CachedPostFile | undefined, now = Date.now(), maxAge = postFileCacheMaxAge): boolean {
  return isCacheStale(cached?.loadedAt, now, maxAge);
}

export function upsertPostSummary(posts: PostSummary[] | undefined, post: PostSummary): PostSummary[] {
  const existing = posts ?? [];
  const next = existing.some((item) => item.path === post.path)
    ? existing.map((item) => item.path === post.path ? post : item)
    : [post, ...existing];
  return sortPostSummaries(next);
}

export function removePostSummary(posts: PostSummary[] | undefined, path: string): PostSummary[] | undefined {
  if (!posts) return undefined;
  return posts.filter((post) => post.path !== path);
}

export function upsertPostFile(posts: Record<string, CachedPostFile>, post: PostFile, loadedAt = Date.now()): Record<string, CachedPostFile> {
  return {
    ...posts,
    [post.path]: { post, loadedAt }
  };
}

export function removePostFile(posts: Record<string, CachedPostFile>, path: string): Record<string, CachedPostFile> {
  const next = { ...posts };
  delete next[path];
  return next;
}
