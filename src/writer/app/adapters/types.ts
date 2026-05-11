import type { AssetFile } from "../core/assets.js";
import type { PostFile, PostSummary, PostStatus } from "../core/posts.js";

export interface AssetUpload {
  path: string;
  contentBase64: string;
  message: string;
}

export interface SavePostChange {
  path: string;
  slug: string;
  status: PostStatus;
  content: string;
  sha?: string;
  media?: AssetUpload[];
}

export interface DeletePostChange {
  path: string;
  slug: string;
  sha?: string;
  mediaPaths?: string[];
}

export interface CommitResult {
  sha?: string;
  htmlUrl?: string;
}

export interface RepositoryAdapter {
  validateConnection(): Promise<void>;
  listPosts(options?: { limit?: number; onPosts?: (posts: PostSummary[], loading: boolean) => void }): Promise<PostSummary[]>;
  readPost(path: string): Promise<PostFile>;
  savePost(change: SavePostChange): Promise<CommitResult>;
  deletePost(change: DeletePostChange): Promise<CommitResult>;
  listAssets(folderPath: string): Promise<AssetFile[]>;
  uploadAsset(asset: AssetUpload): Promise<AssetFile>;
  deleteAssets(paths: string[]): Promise<void>;
}
