import type { WriterPublicConfig } from "../core/config.js";
import type { PostSummary } from "../core/posts.js";

export interface CachedPostSummary {
  path: string;
  sha: string;
  summary: PostSummary;
}

export interface PostSummaryCache {
  get(path: string, sha: string): PostSummary | undefined;
  set(path: string, sha: string, summary: PostSummary): void;
  remove(path: string): void;
  markDeleted(path: string): void;
  isDeleted(path: string): boolean;
  removeMissing(paths: Set<string>): void;
  save(): void;
}

const cacheVersion = 1;
const tombstoneTtl = 5 * 60 * 1000;

function storage(): Storage | undefined {
  if (typeof window === "undefined") return undefined;
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

function cacheKey(config: WriterPublicConfig): string {
  return [
    "inkstead.writer.postSummaries",
    cacheVersion,
    config.provider,
    config.instanceUrl ?? "",
    config.owner ?? "",
    config.repo ?? "",
    config.branch ?? "",
    config.postsPath
  ].join(":");
}

export function createPostSummaryCache(config: WriterPublicConfig): PostSummaryCache {
  const key = cacheKey(config);
  const store = storage();
  const entries = new Map<string, CachedPostSummary>();
  const deleted = new Map<string, number>();
  if (store) {
    const raw = store.getItem(key);
    if (raw) {
      try {
        const cached = JSON.parse(raw) as CachedPostSummary[] | { entries?: CachedPostSummary[]; deleted?: Array<[string, number]> };
        const cachedEntries = Array.isArray(cached) ? cached : cached.entries ?? [];
        for (const entry of cachedEntries) if (entry.path && entry.sha && entry.summary) entries.set(entry.path, entry);
        if (!Array.isArray(cached)) {
          const now = Date.now();
          for (const [path, timestamp] of cached.deleted ?? []) {
            if (now - timestamp < tombstoneTtl) deleted.set(path, timestamp);
          }
        }
      } catch {
        store.removeItem(key);
      }
    }
  }

  return {
    get(path, sha) {
      const entry = entries.get(path);
      return entry?.sha === sha ? entry.summary : undefined;
    },
    set(path, sha, summary) {
      deleted.delete(path);
      entries.set(path, { path, sha, summary });
    },
    remove(path) {
      entries.delete(path);
    },
    markDeleted(path) {
      entries.delete(path);
      deleted.set(path, Date.now());
    },
    isDeleted(path) {
      const timestamp = deleted.get(path);
      if (!timestamp) return false;
      if (Date.now() - timestamp < tombstoneTtl) return true;
      deleted.delete(path);
      return false;
    },
    removeMissing(paths) {
      for (const path of entries.keys()) if (!paths.has(path)) entries.delete(path);
      for (const path of deleted.keys()) if (!paths.has(path)) deleted.delete(path);
    },
    save() {
      if (!store) return;
      store.setItem(key, JSON.stringify({ entries: [...entries.values()], deleted: [...deleted.entries()] }));
    }
  };
}
