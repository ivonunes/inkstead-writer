import type { AssetFile } from "../core/assets.js";
import type { WriterPublicConfig } from "../core/config.js";
import { postDateSortValue, summarizePost, type PostFile, type PostSummary } from "../core/posts.js";
import type { AssetUpload, CommitResult, DeletePostChange, RepositoryAdapter, SavePostChange } from "./types.js";
import { forEachConcurrent } from "./concurrency.js";
import { createPostSummaryCache } from "./summary-cache.js";

interface ForgejoContentItem {
  type: "file" | "dir" | "symlink" | "submodule" | string;
  name: string;
  path: string;
  sha: string;
  content?: string;
  encoding?: string;
}

interface ForgejoTreeItem {
  path: string;
  type: "blob" | "tree" | string;
  sha: string;
}

interface ForgejoTreeResponse {
  tree?: ForgejoTreeItem[];
  truncated?: boolean;
  page?: number;
}

interface ForgejoBlob {
  content?: string;
  encoding?: string;
}

interface ForgejoCommit {
  sha?: string;
  html_url?: string;
}

interface ForgejoFilesResponse {
  commit?: ForgejoCommit;
  files?: ForgejoContentItem[];
}

interface ForgejoFileRef {
  path: string;
  sha: string;
}

interface ForgejoFileOperation {
  operation: "create" | "update" | "delete";
  path: string;
  content?: string;
  sha?: string;
}

export class ForgejoRepositoryAdapter implements RepositoryAdapter {
  private readonly apiBase: string;
  private readonly branch: string;

  constructor(private readonly config: WriterPublicConfig, private readonly token: string) {
    if (!config.owner || !config.repo || !config.branch || !config.instanceUrl) {
      throw new Error("Forgejo Writer config requires instanceUrl, owner, repo, and branch.");
    }
    this.apiBase = `${normalizeInstanceUrl(config.instanceUrl)}/api/v1/repos/${encodeURIComponent(config.owner)}/${encodeURIComponent(config.repo)}`;
    this.branch = config.branch;
  }

  async validateConnection(): Promise<void> {
    await this.getContents(this.config.postsPath);
  }

  async listPosts(options: { limit?: number; onPosts?: (posts: PostSummary[], loading: boolean) => void } = {}): Promise<PostSummary[]> {
    const cache = createPostSummaryCache(this.config);
    const providerFiles = await this.listMarkdownFiles();
    const allFiles = sortFileRefs(providerFiles.filter((file) => !cache.isDeleted(file.path)));
    const files = options.limit ? allFiles.slice(0, options.limit) : allFiles;
    const filePaths = new Set(providerFiles.map((file) => file.path));
    cache.removeMissing(filePaths);
    const posts: PostSummary[] = [];
    const missing: ForgejoFileRef[] = [];

    for (const file of files) {
      const cached = cache.get(file.path, file.sha);
      if (cached) posts.push(cached);
      else missing.push(file);
    }
    if (posts.length > 0) options.onPosts?.(sortPosts(posts), missing.length > 0);

    await forEachConcurrent(missing, 5, async (file) => {
      const post = await this.readPostBlob(file);
      posts.push(post);
      cache.set(file.path, file.sha, post);
      options.onPosts?.(sortPosts(posts), true);
    });
    cache.save();
    const sorted = sortPosts(posts);
    options.onPosts?.(sorted, false);
    return sorted;
  }

  async readPost(filePath: string): Promise<PostFile> {
    const file = await this.getFile(filePath);
    const content = decodeBase64(file.content ?? "");
    return { ...summarizePost(filePath, content), content, sha: file.sha };
  }

  async savePost(change: SavePostChange): Promise<CommitResult> {
    const existing = change.sha ? await this.getFile(change.path) : await this.getFile(change.path).catch(() => undefined);
    if (existing && !change.sha) throw new Error(`${change.path} already exists.`);
    if (change.sha && existing?.sha && existing.sha !== change.sha) throw new Error("Forgejo reported a file conflict. Reload the post and try again.");
    await this.ensureMediaPathsAvailable(change.media ?? []);

    const action = existing ? change.status === "published" ? "Publish" : "Update" : "Create";
    const result = await this.changeFiles([
      {
        operation: existing ? "update" : "create",
        path: change.path,
        content: encodeBase64(change.content),
        sha: existing?.sha
      },
      ...(change.media ?? []).map((asset) => ({
        operation: "create" as const,
        path: asset.path,
        content: asset.contentBase64
      }))
    ], `${action} post: ${change.slug}`);
    const cache = createPostSummaryCache(this.config);
    cache.remove(change.path);
    cache.save();
    return { sha: result.commit?.sha, htmlUrl: result.commit?.html_url };
  }

  async deletePost(change: DeletePostChange): Promise<CommitResult> {
    if (change.sha) {
      const existing = await this.getFile(change.path);
      if (existing.sha !== change.sha) throw new Error("Forgejo reported a file conflict. Reload the post and try again.");
    }
    const paths = await this.existingPaths([change.path, ...change.mediaPaths ?? []]);
    const result = await this.deletePaths(paths, `Delete post: ${change.slug}`);
    const cache = createPostSummaryCache(this.config);
    cache.markDeleted(change.path);
    cache.save();
    return { sha: result.commit?.sha, htmlUrl: result.commit?.html_url };
  }

  async listAssets(folderPath: string): Promise<AssetFile[]> {
    const items = await this.getContents(folderPath).catch((error) => {
      if (error instanceof Error && error.message.includes("not found")) return [] as ForgejoContentItem[];
      throw error;
    });
    if (!Array.isArray(items)) return [];
    return items
      .filter((item) => item.type === "file")
      .map((item) => ({ path: item.path, name: item.name, sha: item.sha }));
  }

  async uploadAsset(asset: AssetUpload): Promise<AssetFile> {
    const existing = await this.getFile(asset.path).catch(() => undefined);
    if (existing) throw new Error(`${asset.path} already exists.`);
    const result = await this.changeFiles([{
      operation: "create",
      path: asset.path,
      content: asset.contentBase64
    }], asset.message);
    const file = result.files?.find((item) => item.path === asset.path);
    return { path: file?.path ?? asset.path, name: file?.name ?? asset.path.split("/").at(-1) ?? asset.path, sha: file?.sha };
  }

  async deleteAssets(paths: string[]): Promise<void> {
    const existing = await this.existingPaths(paths);
    if (existing.length > 0) await this.deletePaths(existing, "Delete media");
  }

  private async listMarkdownFiles(): Promise<ForgejoFileRef[]> {
    const tree = await this.listTreeRecursive().catch(() => undefined);
    if (tree) {
      const prefix = `${this.config.postsPath.replace(/\/+$/g, "")}/`;
      return tree
        .filter((item) => item.type === "blob" && item.path.startsWith(prefix) && item.path.endsWith(".md"))
        .map((item) => ({ path: item.path, sha: item.sha }));
    }
    return (await this.walkMarkdown(this.config.postsPath)).map((item) => ({ path: item.path, sha: item.sha }));
  }

  private async listTreeRecursive(): Promise<ForgejoTreeItem[]> {
    const output: ForgejoTreeItem[] = [];
    let page = 1;
    while (true) {
      const params = new URLSearchParams({
        recursive: "true",
        page: String(page),
        per_page: "1000"
      });
      const result = await this.request<ForgejoTreeResponse>(`${this.apiBase}/git/trees/${encodeURIComponent(this.branch)}?${params.toString()}`);
      output.push(...result.tree ?? []);
      if (!result.truncated) return output;
      page = (result.page ?? page) + 1;
    }
  }

  private async walkMarkdown(folderPath: string): Promise<ForgejoContentItem[]> {
    const items = await this.getContents(folderPath);
    if (!Array.isArray(items)) return items.path.endsWith(".md") ? [items] : [];
    const output: ForgejoContentItem[] = [];
    for (const item of items) {
      if (item.type === "dir") output.push(...await this.walkMarkdown(item.path));
      if (item.type === "file" && item.path.endsWith(".md")) output.push(item);
    }
    return output;
  }

  private async getContents(filePath: string): Promise<ForgejoContentItem[] | ForgejoContentItem> {
    return this.request<ForgejoContentItem[] | ForgejoContentItem>(this.contentUrl(filePath));
  }

  private async getFile(filePath: string): Promise<ForgejoContentItem> {
    const item = await this.getContents(filePath);
    if (Array.isArray(item) || item.type !== "file") throw new Error(`${filePath} is not a file.`);
    return item;
  }

  private async readPostBlob(file: ForgejoFileRef): Promise<PostSummary> {
    const blob = await this.request<ForgejoBlob>(`${this.apiBase}/git/blobs/${encodeURIComponent(file.sha)}`);
    const content = decodeBase64(blob.content ?? "");
    return summarizePost(file.path, content);
  }

  private async existingPaths(paths: string[]): Promise<ForgejoFileRef[]> {
    const existing: ForgejoFileRef[] = [];
    await forEachConcurrent([...new Set(paths)], 4, async (filePath) => {
      const file = await this.getFile(filePath).catch(() => undefined);
      if (file) existing.push({ path: filePath, sha: file.sha });
    });
    return existing;
  }

  private async ensureMediaPathsAvailable(assets: AssetUpload[]): Promise<void> {
    await forEachConcurrent(assets, 4, async (asset) => {
      const existing = await this.getFile(asset.path).catch(() => undefined);
      if (existing) throw new Error(`${asset.path} already exists.`);
    });
  }

  private async deletePaths(paths: ForgejoFileRef[], message: string): Promise<ForgejoFilesResponse> {
    if (paths.length === 0) throw new Error("No files were found to delete.");
    return this.changeFiles(paths.map((file) => ({
      operation: "delete",
      path: file.path,
      sha: file.sha
    })), message);
  }

  private async changeFiles(files: ForgejoFileOperation[], message: string): Promise<ForgejoFilesResponse> {
    return this.request<ForgejoFilesResponse>(`${this.apiBase}/contents`, {
      method: "POST",
      body: JSON.stringify({
        branch: this.branch,
        message,
        files
      })
    });
  }

  private contentUrl(filePath: string): string {
    const cleanPath = filePath.split("/").map(encodeURIComponent).join("/");
    return `${this.apiBase}/contents/${cleanPath}?ref=${encodeURIComponent(this.branch)}`;
  }

  private async request<T>(url: string, init: RequestInit = {}, retry = true): Promise<T> {
    const response = await fetch(url, {
      ...init,
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: `token ${this.token}`,
        ...init.headers
      }
    });
    const retryAfter = retryDelay(response);
    if (retry && retryAfter !== undefined) {
      await delay(retryAfter);
      return this.request<T>(url, init, false);
    }
    if (!response.ok) throw new Error(await forgejoError(response));
    return response.status === 204 ? undefined as T : response.json() as Promise<T>;
  }
}

function normalizeInstanceUrl(value: string): string {
  const trimmed = value.trim().replace(/\/+$/g, "");
  return trimmed.endsWith("/api/v1") ? trimmed.slice(0, -"/api/v1".length) : trimmed;
}

function retryDelay(response: Response): number | undefined {
  if (response.status !== 429) return undefined;
  const retryAfter = Number(response.headers.get("retry-after"));
  if (!Number.isFinite(retryAfter) || retryAfter < 0) return undefined;
  return Math.min(retryAfter * 1000, 5000);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function sortPosts(posts: PostSummary[]): PostSummary[] {
  return [...posts].sort((a, b) => postDateSortValue(b).localeCompare(postDateSortValue(a)));
}

function sortFileRefs<T extends { path: string }>(files: T[]): T[] {
  return [...files].sort((a, b) => b.path.localeCompare(a.path));
}

async function forgejoError(response: Response): Promise<string> {
  const body = await response.json().catch(() => ({})) as { message?: string };
  if (response.status === 401 || response.status === 403) return "Forgejo rejected the token or the token is missing write:repository permission.";
  if (response.status === 404) return "Forgejo repository, branch, or path was not found.";
  if (response.status === 409) return "Forgejo reported a file conflict. Reload the post and try again.";
  return body.message ? `Forgejo error: ${body.message}` : `Forgejo request failed with status ${response.status}.`;
}

function encodeBase64(value: string): string {
  return btoa(unescape(encodeURIComponent(value)));
}

function decodeBase64(value: string): string {
  return decodeURIComponent(escape(atob(value.replace(/\n/g, ""))));
}
