import type { SyndicationProvider } from "./config.js";
import type { PostStatus } from "./posts.js";

export function canEditSyndicationTargets(status: PostStatus): boolean {
  return status === "draft";
}

export function shouldShowSyndicationTargets(status: PostStatus, providers: readonly SyndicationProvider[]): boolean {
  return canEditSyndicationTargets(status) && providers.length > 0;
}

export function shouldShowCategoryTargets(categories: readonly string[]): boolean {
  return categories.length > 0;
}

export function syndicationTargetsFromFrontmatter(value: unknown, fallback: SyndicationProvider[]): SyndicationProvider[] {
  if (!Array.isArray(value)) return fallback;
  return value.filter((item): item is SyndicationProvider => fallback.includes(item as SyndicationProvider));
}

export function categoriesFromFrontmatter(value: unknown, configuredCategories: string[]): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && configuredCategories.includes(item));
}

export function unmanagedCategoriesFromFrontmatter(value: unknown, configuredCategories: string[]): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && !configuredCategories.includes(item));
}
