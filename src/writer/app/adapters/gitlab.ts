import type { AssetFile } from "../core/assets.js";
import type { WriterPublicConfig } from "../core/config.js";
import { postDateSortValue, summarizePost, type PostFile, type PostSummary } from "../core/posts.js";
import type { AssetUpload, CommitResult, DeletePostChange, RepositoryAdapter, SavePostChange } from "./types.js";
import { forEachConcurrent } from "./concurrency.js";
import { createPostSummaryCache } from "./summary-cache.js";

interface GitLabTreeItem {
  id: string;
  name: string;
  path: string;
  type: "tree" | "blob";
}

interface GitLabFile {
  file_path: string;
  file_name: string;
  blob_id: string;
  content: string;
  encoding: "base64" | string;
}

interface GitLabCommitResult {
  id?: string;
  web_url?: string;
}

interface GitLabBlob {
  content: string;
  encoding: "base64" | string;
}

export class GitLabRepositoryAdapter implements RepositoryAdapter {
  private readonly apiBase: string;
  private readonly projectId: string;
  private readonly branch: string;

  constructor(private readonly config: WriterPublicConfig, private readonly token: string) {
    if (!config.owner || !config.repo || !config.branch) throw new Error("GitLab Writer config requires owner, repo, and branch.");
    this.projectId = encodeURIComponent(`${config.owner}/${config.repo}`);
    this.apiBase = `https://gitlab.com/api/v4/projects/${this.projectId}`;
    this.branch = config.branch;
  }

  async validateConnection(): Promise<void> {
    await this.listTree(this.config.postsPath, false);
  }

  async listPosts(options: { limit?: number; onPosts?: (posts: PostSummary[], loading: boolean) => void } = {}): Promise<PostSummary[]> {
    const cache = createPostSummaryCache(this.config);
    const providerFiles = (await this.listTree(this.config.postsPath, true))
      .filter((item) => item.type === "blob" && item.path.endsWith(".md"));
    const allFiles = sortFileRefs(providerFiles.filter((item) => !cache.isDeleted(item.path)));
    const files = options.limit ? allFiles.slice(0, options.limit) : allFiles;
    const filePaths = new Set(providerFiles.map((file) => file.path));
    cache.removeMissing(filePaths);
    const posts: PostSummary[] = [];
    const missing: GitLabTreeItem[] = [];

    for (const file of files) {
      const cached = cache.get(file.path, file.id);
      if (cached) posts.push(cached);
      else missing.push(file);
    }
    if (posts.length > 0) options.onPosts?.(sortPosts(posts), missing.length > 0);

    await forEachConcurrent(missing, 5, async (file) => {
      const post = await this.readPostBlob(file);
      posts.push(post);
      cache.set(file.path, file.id, post);
      options.onPosts?.(sortPosts(posts), true);
    });
    cache.save();
    const sorted = sortPosts(posts);
    options.onPosts?.(sorted, false);
    return sorted;
  }

  async readPost(filePath: string): Promise<PostFile> {
    const file = await this.getFile(filePath);
    const content = decodeBase64(file.content);
    return { ...summarizePost(filePath, content), content, sha: file.blob_id };
  }

  async savePost(change: SavePostChange): Promise<CommitResult> {
    if (change.media?.length) return this.savePostWithMedia(change);
    const exists = Boolean(change.sha) || Boolean(await this.getFile(change.path).catch(() => undefined));
    if (exists && !change.sha) throw new Error(`${change.path} already exists.`);
    const action = exists ? change.status === "published" ? "Publish" : "Update" : "Create";
    const result = await this.request<GitLabCommitResult>(this.fileUrl(change.path, false), {
      method: exists ? "PUT" : "POST",
      body: JSON.stringify({
        branch: this.branch,
        commit_message: `${action} post: ${change.slug}`,
        content: encodeBase64(change.content),
        encoding: "base64"
      })
    });
    const cache = createPostSummaryCache(this.config);
    cache.remove(change.path);
    cache.save();
    return { sha: result.id, htmlUrl: result.web_url };
  }

  private async savePostWithMedia(change: SavePostChange): Promise<CommitResult> {
    const exists = Boolean(change.sha) || Boolean(await this.getFile(change.path).catch(() => undefined));
    if (exists && !change.sha) throw new Error(`${change.path} already exists.`);
    await this.ensureMediaPathsAvailable(change.media ?? []);
    const action = exists ? change.status === "published" ? "Publish" : "Update" : "Create";
    const result = await this.request<GitLabCommitResult>(`${this.apiBase}/repository/commits`, {
      method: "POST",
      body: JSON.stringify({
        branch: this.branch,
        commit_message: `${action} post: ${change.slug}`,
        actions: [
          {
            action: exists ? "update" : "create",
            file_path: change.path,
            content: encodeBase64(change.content),
            encoding: "base64"
          },
          ...(change.media ?? []).map((asset) => ({
            action: "create",
            file_path: asset.path,
            content: asset.contentBase64,
            encoding: "base64"
          }))
        ]
      })
    });
    const cache = createPostSummaryCache(this.config);
    cache.remove(change.path);
    cache.save();
    return { sha: result.id, htmlUrl: result.web_url };
  }

  async deletePost(change: DeletePostChange): Promise<CommitResult> {
    const paths = await this.existingPaths([change.path, ...change.mediaPaths ?? []]);
    const result = await this.deletePaths(paths, `Delete post: ${change.slug}`);
    const cache = createPostSummaryCache(this.config);
    cache.markDeleted(change.path);
    cache.save();
    return { sha: result.id, htmlUrl: result.web_url };
  }

  async listAssets(folderPath: string): Promise<AssetFile[]> {
    const items = await this.listTree(folderPath, false).catch((error) => {
      if (error instanceof Error && error.message.includes("not found")) return [] as GitLabTreeItem[];
      throw error;
    });
    return items
      .filter((item) => item.type === "blob")
      .map((item) => ({ path: item.path, name: item.name, sha: item.id }));
  }

  async uploadAsset(asset: AssetUpload): Promise<AssetFile> {
    const existing = await this.getFile(asset.path).catch(() => undefined);
    if (existing) throw new Error(`${asset.path} already exists.`);
    const result = await this.request<GitLabFile>(this.fileUrl(asset.path, false), {
      method: "POST",
      body: JSON.stringify({
        branch: this.branch,
        commit_message: asset.message,
        content: asset.contentBase64,
        encoding: "base64"
      })
    });
    return { path: result.file_path, name: result.file_name, sha: result.blob_id };
  }

  async deleteAssets(paths: string[]): Promise<void> {
    const existing = await this.existingPaths(paths);
    if (existing.length > 0) await this.deletePaths(existing, "Delete media");
  }

  private async listTree(folderPath: string, recursive: boolean): Promise<GitLabTreeItem[]> {
    const params = new URLSearchParams({
      path: folderPath,
      ref: this.branch,
      recursive: String(recursive),
      per_page: "100"
    });
    return this.request<GitLabTreeItem[]>(`${this.apiBase}/repository/tree?${params.toString()}`);
  }

  private async getFile(filePath: string): Promise<GitLabFile> {
    return this.request<GitLabFile>(this.fileUrl(filePath));
  }

  private async readPostBlob(file: GitLabTreeItem): Promise<PostSummary> {
    const blob = await this.request<GitLabBlob>(`${this.apiBase}/repository/blobs/${encodeURIComponent(file.id)}`);
    const content = decodeBase64(blob.content);
    return summarizePost(file.path, content);
  }

  private async existingPaths(paths: string[]): Promise<string[]> {
    const existing: string[] = [];
    await forEachConcurrent([...new Set(paths)], 4, async (filePath) => {
      const file = await this.getFile(filePath).catch(() => undefined);
      if (file) existing.push(filePath);
    });
    return existing;
  }

  private async ensureMediaPathsAvailable(assets: AssetUpload[]): Promise<void> {
    await forEachConcurrent(assets, 4, async (asset) => {
      const existing = await this.getFile(asset.path).catch(() => undefined);
      if (existing) throw new Error(`${asset.path} already exists.`);
    });
  }

  private async deletePaths(paths: string[], message: string): Promise<GitLabCommitResult> {
    if (paths.length === 0) throw new Error("No files were found to delete.");
    return this.request<GitLabCommitResult>(`${this.apiBase}/repository/commits`, {
      method: "POST",
      body: JSON.stringify({
        branch: this.branch,
        commit_message: message,
        actions: paths.map((filePath) => ({
          action: "delete",
          file_path: filePath
        }))
      })
    });
  }

  private fileUrl(filePath: string, includeRef = true): string {
    const base = `${this.apiBase}/repository/files/${encodeURIComponent(filePath)}`;
    return includeRef ? `${base}?ref=${encodeURIComponent(this.branch)}` : base;
  }

  private async request<T>(url: string, init: RequestInit = {}, retry = true): Promise<T> {
    const response = await fetch(url, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        "PRIVATE-TOKEN": this.token,
        ...init.headers
      }
    });
    const retryAfter = retryDelay(response);
    if (retry && retryAfter !== undefined) {
      await delay(retryAfter);
      return this.request<T>(url, init, false);
    }
    if (!response.ok) throw new Error(await gitlabError(response));
    return response.status === 204 ? undefined as T : response.json() as Promise<T>;
  }
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

async function gitlabError(response: Response): Promise<string> {
  const body = await response.json().catch(() => ({})) as { message?: string | Record<string, string[]> };
  if (response.status === 401 || response.status === 403) return "GitLab rejected the token or the token is missing repository read/write permissions.";
  if (response.status === 404) return "GitLab project, branch, or path was not found.";
  if (response.status === 400 || response.status === 409) return "GitLab reported a file conflict. Reload the post and try again.";
  if (typeof body.message === "string") return `GitLab error: ${body.message}`;
  return `GitLab request failed with status ${response.status}.`;
}

function encodeBase64(value: string): string {
  return btoa(unescape(encodeURIComponent(value)));
}

function decodeBase64(value: string): string {
  return decodeURIComponent(escape(atob(value.replace(/\n/g, ""))));
}
