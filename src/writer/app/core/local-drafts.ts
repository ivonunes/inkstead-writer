import type { WriterPublicConfig } from "./config.js";

export interface LocalWriterDraft {
  title: string;
  body: string;
  syndicationTargets: string[];
  categoryTargets: string[];
  updatedAt: number;
}

const draftVersion = 1;
const newPostIdentifier = "__new__";

function storage(): Storage | undefined {
  try {
    return globalThis.localStorage;
  } catch {
    return undefined;
  }
}

export function localDraftIdentifier(path: string | undefined): string {
  return path ?? newPostIdentifier;
}

export function localDraftKey(config: WriterPublicConfig, identifier: string): string {
  return [
    "inkstead.writer.localDraft",
    draftVersion,
    config.provider,
    config.owner ?? "",
    config.repo ?? "",
    config.branch ?? "",
    config.postsPath,
    identifier
  ].join(":");
}

export function loadLocalWriterDraft(config: WriterPublicConfig, identifier: string): LocalWriterDraft | undefined {
  const store = storage();
  if (!store) return undefined;
  try {
    const raw = store.getItem(localDraftKey(config, identifier));
    if (!raw) return undefined;
    const draft = JSON.parse(raw) as LocalWriterDraft;
    if (typeof draft.title !== "string" || typeof draft.body !== "string" || typeof draft.updatedAt !== "number") return undefined;
    return {
      title: draft.title,
      body: draft.body,
      syndicationTargets: Array.isArray(draft.syndicationTargets) ? draft.syndicationTargets.filter((target) => typeof target === "string") : [],
      categoryTargets: Array.isArray(draft.categoryTargets) ? draft.categoryTargets.filter((target) => typeof target === "string") : [],
      updatedAt: draft.updatedAt
    };
  } catch {
    return undefined;
  }
}

export function saveLocalWriterDraft(config: WriterPublicConfig, identifier: string, draft: Omit<LocalWriterDraft, "updatedAt">): void {
  const store = storage();
  if (!store) return;
  try {
    store.setItem(localDraftKey(config, identifier), JSON.stringify({ ...draft, updatedAt: Date.now() }));
  } catch {
    // Local recovery is best-effort. Repository saves remain the source of truth.
  }
}

export function clearLocalWriterDraft(config: WriterPublicConfig, identifier: string): void {
  const store = storage();
  if (!store) return;
  try {
    store.removeItem(localDraftKey(config, identifier));
  } catch {
    // Ignore unavailable browser storage.
  }
}
