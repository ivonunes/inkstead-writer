import type { AssetFile } from "../core/assets.js";
import type { PostFile, PostSummary } from "../core/posts.js";
import type { AssetUpload, CommitResult, DeletePostChange, RepositoryAdapter, SavePostChange } from "./types.js";

export class LocalRepositoryAdapter implements RepositoryAdapter {
  async validateConnection(): Promise<void> {
    await request("/validate");
  }

  async listPosts(): Promise<PostSummary[]> {
    return request<PostSummary[]>("/posts");
  }

  async readPost(path: string): Promise<PostFile> {
    return request<PostFile>(`/post?path=${encodeURIComponent(path)}`);
  }

  async savePost(change: SavePostChange): Promise<CommitResult> {
    return request<CommitResult>("/post", {
      method: "PUT",
      body: JSON.stringify(change)
    });
  }

  async deletePost(change: DeletePostChange): Promise<CommitResult> {
    return request<CommitResult>("/post", {
      method: "DELETE",
      body: JSON.stringify(change)
    });
  }

  async listAssets(folderPath: string): Promise<AssetFile[]> {
    return request<AssetFile[]>(`/assets?folder=${encodeURIComponent(folderPath)}`);
  }

  async uploadAsset(asset: AssetUpload): Promise<AssetFile> {
    return request<AssetFile>("/asset", {
      method: "PUT",
      body: JSON.stringify(asset)
    });
  }

  async deleteAssets(paths: string[]): Promise<void> {
    await request("/assets", {
      method: "DELETE",
      body: JSON.stringify({ paths })
    });
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`/__inkstead-writer/api${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...init.headers
    }
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({})) as { error?: string };
    throw new Error(body.error ?? "Local Writer request failed.");
  }
  return response.json() as Promise<T>;
}
