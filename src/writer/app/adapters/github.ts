import type { WriterPublicConfig } from "../core/config.js";
import { postDateSortValue, summarizePost, type PostFile, type PostSummary } from "../core/posts.js";
import type { AssetFile } from "../core/assets.js";
import type { AssetUpload, CommitResult, DeletePostChange, RepositoryAdapter, SavePostChange } from "./types.js";
import { forEachConcurrent } from "./concurrency.js";
import { createPostSummaryCache } from "./summary-cache.js";

interface GitHubContentItem {
  type: "file" | "dir";
  name: string;
  path: string;
  sha: string;
  content?: string;
  encoding?: string;
  download_url?: string | null;
}

interface GitHubTreeResponse {
  tree?: Array<{
    path: string;
    type: "blob" | "tree" | string;
    sha: string;
  }>;
}

interface GitHubBlob {
  content?: string;
  encoding?: string;
}

interface GitHubRef {
  object?: {
    sha?: string;
  };
}

interface GitHubCommit {
  sha: string;
  html_url?: string;
  tree?: {
    sha?: string;
  };
}

interface GitHubPostFileRef {
  path: string;
  sha: string;
}

export class GitHubRepositoryAdapter implements RepositoryAdapter {
  private readonly apiBase: string;
  private readonly branch: string;
  private headSha: string | undefined;

  constructor(private readonly config: WriterPublicConfig, private readonly token: string) {
    if (!config.owner || !config.repo || !config.branch) throw new Error("GitHub Writer config requires owner, repo, and branch.");
    this.apiBase = `https://api.github.com/repos/${config.owner}/${config.repo}`;
    this.branch = config.branch;
  }

  async validateConnection(): Promise<void> {
    await this.request(this.contentUrl(this.config.postsPath));
  }

  async listPosts(options: { limit?: number; onPosts?: (posts: PostSummary[], loading: boolean) => void } = {}): Promise<PostSummary[]> {
    const cache = createPostSummaryCache(this.config);
    const providerFiles = await this.listMarkdownFiles();
    const allFiles = sortFileRefs(providerFiles.filter((file) => !cache.isDeleted(file.path)));
    const files = options.limit ? allFiles.slice(0, options.limit) : allFiles;
    const filePaths = new Set(providerFiles.map((file) => file.path));
    cache.removeMissing(filePaths);
    const posts: PostSummary[] = [];
    const missing: GitHubPostFileRef[] = [];

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
    const item = await this.getFile(filePath);
    const content = decodeBase64(item.content ?? "");
    return { ...summarizePost(filePath, content), content, sha: item.sha };
  }

  async savePost(change: SavePostChange): Promise<CommitResult> {
    if (change.media?.length) return this.savePostWithMedia(change);
    const existing = change.sha ? { sha: change.sha } : await this.getFile(change.path).catch(() => undefined);
    if (existing && !change.sha) throw new Error(`${change.path} already exists.`);
    const action = existing ? change.status === "published" ? "Publish" : "Update" : "Create";
    const result = await this.request<{ commit?: { sha?: string; html_url?: string } }>(this.contentUrl(change.path), {
      method: "PUT",
      body: JSON.stringify({
        message: `${action} post: ${change.slug}`,
        content: encodeBase64(change.content),
        branch: this.branch,
        sha: existing?.sha
      })
    });
    const cache = createPostSummaryCache(this.config);
    cache.remove(change.path);
    cache.save();
    return { sha: result.commit?.sha, htmlUrl: result.commit?.html_url };
  }

  private async savePostWithMedia(change: SavePostChange): Promise<CommitResult> {
    const existing = change.sha ? { sha: change.sha } : await this.getFile(change.path).catch(() => undefined);
    if (existing && !change.sha) throw new Error(`${change.path} already exists.`);
    if (change.sha && existing?.sha !== change.sha) throw new Error("GitHub reported a file conflict. Reload the post and try again.");
    await this.ensureMediaPathsAvailable(change.media ?? []);
    const action = existing ? change.status === "published" ? "Publish" : "Update" : "Create";
    const result = await this.commitFiles([
      { path: change.path, content: change.content },
      ...(change.media ?? []).map((asset) => ({ path: asset.path, contentBase64: asset.contentBase64 }))
    ], `${action} post: ${change.slug}`);
    const cache = createPostSummaryCache(this.config);
    cache.remove(change.path);
    cache.save();
    return { sha: result.sha, htmlUrl: result.html_url };
  }

  async deletePost(change: DeletePostChange): Promise<CommitResult> {
    if (change.sha) {
      const existing = await this.getFile(change.path);
      if (existing.sha !== change.sha) throw new Error("GitHub reported a file conflict. Reload the post and try again.");
    }
    const paths = await this.existingPaths([change.path, ...change.mediaPaths ?? []]);
    const result = await this.deletePaths(paths, `Delete post: ${change.slug}`);
    const cache = createPostSummaryCache(this.config);
    cache.markDeleted(change.path);
    cache.save();
    return { sha: result.sha, htmlUrl: result.html_url };
  }

  async listAssets(folderPath: string): Promise<AssetFile[]> {
    const items = await this.request<GitHubContentItem[] | GitHubContentItem>(this.contentUrl(folderPath)).catch((error) => {
      if (error instanceof Error && error.message.includes("not found")) return [] as GitHubContentItem[];
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
    const item = await this.request<{ content: GitHubContentItem }>(this.contentUrl(asset.path), {
      method: "PUT",
      body: JSON.stringify({
        message: asset.message,
        branch: this.branch,
        content: asset.contentBase64
      })
    });
    return { path: item.content.path, name: item.content.name, sha: item.content.sha };
  }

  async deleteAssets(paths: string[]): Promise<void> {
    const existing = await this.existingPaths(paths);
    if (existing.length > 0) await this.deletePaths(existing, "Delete media");
  }

  private async listMarkdownFiles(): Promise<GitHubPostFileRef[]> {
    const tree = await this.request<GitHubTreeResponse>(`${this.apiBase}/git/trees/${encodeURIComponent(this.branch)}?recursive=1`).catch(() => undefined);
    if (tree?.tree) {
      const prefix = `${this.config.postsPath.replace(/\/+$/g, "")}/`;
      return tree.tree
        .filter((item) => item.type === "blob" && item.path.startsWith(prefix) && item.path.endsWith(".md"))
        .map((item) => ({ path: item.path, sha: item.sha }));
    }
    return (await this.walkMarkdown(this.config.postsPath)).map((item) => ({ path: item.path, sha: item.sha }));
  }

  private async walkMarkdown(folderPath: string): Promise<GitHubContentItem[]> {
    const items = await this.request<GitHubContentItem[] | GitHubContentItem>(this.contentUrl(folderPath));
    if (!Array.isArray(items)) return items.path.endsWith(".md") ? [items] : [];
    const output: GitHubContentItem[] = [];
    for (const item of items) {
      if (item.type === "dir") output.push(...await this.walkMarkdown(item.path));
      if (item.type === "file" && item.path.endsWith(".md")) output.push(item);
    }
    return output;
  }

  private async getFile(filePath: string): Promise<GitHubContentItem> {
    const item = await this.request<GitHubContentItem[] | GitHubContentItem>(this.contentUrl(filePath));
    if (Array.isArray(item) || item.type !== "file") throw new Error(`${filePath} is not a file.`);
    return item;
  }

  private async readPostBlob(file: GitHubPostFileRef): Promise<PostSummary> {
    const blob = await this.request<GitHubBlob>(`${this.apiBase}/git/blobs/${file.sha}`);
    const content = decodeBase64(blob.content ?? "");
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

  private async commitFiles(files: Array<{ path: string; content?: string; contentBase64?: string }>, message: string): Promise<GitHubCommit> {
    return this.withFastForwardRetry(() => this.commitFilesOnce(files, message));
  }

  private async commitFilesOnce(files: Array<{ path: string; content?: string; contentBase64?: string }>, message: string): Promise<GitHubCommit> {
    const parentSha = await this.currentHeadSha();
    const parent = await this.request<GitHubCommit>(`${this.apiBase}/git/commits/${parentSha}`);
    const blobs = await Promise.all(files.map(async (file) => ({
      path: file.path,
      mode: "100644",
      type: "blob",
      sha: (await this.request<{ sha: string }>(`${this.apiBase}/git/blobs`, {
        method: "POST",
        body: JSON.stringify({
          content: file.contentBase64 ?? encodeBase64(file.content ?? ""),
          encoding: "base64"
        })
      })).sha
    })));
    const tree = await this.request<{ sha: string }>(`${this.apiBase}/git/trees`, {
      method: "POST",
      body: JSON.stringify({
        base_tree: parent.tree?.sha,
        tree: blobs
      })
    });
    const commit = await this.request<GitHubCommit>(`${this.apiBase}/git/commits`, {
      method: "POST",
      body: JSON.stringify({
        message,
        tree: tree.sha,
        parents: [parentSha]
      })
    });
    await this.updateHeadSha(commit.sha);
    return commit;
  }

  private async deletePaths(paths: string[], message: string): Promise<GitHubCommit> {
    if (paths.length === 0) throw new Error("No files were found to delete.");
    return this.withFastForwardRetry(() => this.deletePathsOnce(paths, message));
  }

  private async deletePathsOnce(paths: string[], message: string): Promise<GitHubCommit> {
    const parentSha = await this.currentHeadSha();
    const parent = await this.request<GitHubCommit>(`${this.apiBase}/git/commits/${parentSha}`);
    const tree = await this.request<{ sha: string }>(`${this.apiBase}/git/trees`, {
      method: "POST",
      body: JSON.stringify({
        base_tree: parent.tree?.sha,
        tree: paths.map((filePath) => ({
          path: filePath,
          mode: "100644",
          type: "blob",
          sha: null
        }))
      })
    });
    const commit = await this.request<GitHubCommit>(`${this.apiBase}/git/commits`, {
      method: "POST",
      body: JSON.stringify({
        message,
        tree: tree.sha,
        parents: [parentSha]
      })
    });
    await this.updateHeadSha(commit.sha);
    return commit;
  }

  private async withFastForwardRetry(operation: () => Promise<GitHubCommit>): Promise<GitHubCommit> {
    try {
      return await operation();
    } catch (error) {
      if (!(error instanceof Error) || !error.message.toLowerCase().includes("fast forward")) throw error;
      this.headSha = undefined;
      return operation();
    }
  }

  private async currentHeadSha(): Promise<string> {
    if (this.headSha) return this.headSha;
    const ref = await this.request<GitHubRef>(`${this.apiBase}/git/ref/heads/${encodeURIComponent(this.branch)}`);
    const sha = ref.object?.sha;
    if (!sha) throw new Error("GitHub branch head was not found.");
    this.headSha = sha;
    return sha;
  }

  private async updateHeadSha(sha: string): Promise<void> {
    await this.request(`${this.apiBase}/git/refs/heads/${encodeURIComponent(this.branch)}`, {
      method: "PATCH",
      body: JSON.stringify({ sha })
    });
    this.headSha = sha;
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
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${this.token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...init.headers
      }
    });
    const retryAfter = retryDelay(response);
    if (retry && retryAfter !== undefined) {
      await delay(retryAfter);
      return this.request<T>(url, init, false);
    }
    if (!response.ok) throw new Error(await githubError(response));
    return response.status === 204 ? undefined as T : response.json() as Promise<T>;
  }
}

function retryDelay(response: Response): number | undefined {
  if (response.status !== 429 && !(response.status === 403 && response.headers.get("x-ratelimit-remaining") === "0")) return undefined;
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

async function githubError(response: Response): Promise<string> {
  const body = await response.json().catch(() => ({})) as { message?: string };
  if (response.status === 401 || response.status === 403) return "GitHub rejected the token or the token is missing Contents read/write permissions.";
  if (response.status === 404) return "GitHub repository, branch, or path was not found.";
  if (response.status === 409) return "GitHub reported a file conflict. Reload the post and try again.";
  return body.message ? `GitHub error: ${body.message}` : `GitHub request failed with status ${response.status}.`;
}

function encodeBase64(value: string): string {
  return btoa(unescape(encodeURIComponent(value)));
}

function decodeBase64(value: string): string {
  return decodeURIComponent(escape(atob(value.replace(/\n/g, ""))));
}
