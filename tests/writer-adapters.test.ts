import { describe, expect, it } from "vitest";
import { buildPostMarkdown } from "../src/writer/app/core/posts.js";
import { ForgejoRepositoryAdapter } from "../src/writer/app/adapters/forgejo.js";
import { GitHubRepositoryAdapter } from "../src/writer/app/adapters/github.js";
import { GitLabRepositoryAdapter } from "../src/writer/app/adapters/gitlab.js";

function decodeBase64(value: string): string {
  return Buffer.from(value, "base64").toString("utf8");
}

describe("writer adapters", () => {
  it("supports GitLab Writer config and validates through the GitLab API", async () => {
    const requests: Array<{ url: string; token: string | null }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init) => {
      const url = String(input);
      requests.push({ url, token: new Headers(init?.headers).get("PRIVATE-TOKEN") });
      if (url.includes("/repository/tree?")) return new Response("[]", { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "group/subgroup",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await adapter.validateConnection();
      expect(requests[0].url).toContain("https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fsite/repository/tree?");
      expect(requests[0].url).toContain("path=content%2Fposts");
      expect(requests[0].url).toContain("ref=main");
      expect(requests[0].token).toBe("pat");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("supports Forgejo Writer config and validates through the Forgejo API", async () => {
    const requests: Array<{ url: string; authorization: string | null }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init) => {
      const url = String(input);
      requests.push({ url, authorization: new Headers(init?.headers).get("Authorization") });
      if (url.includes("/contents/content/posts?")) return new Response("[]", { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new ForgejoRepositoryAdapter({
        provider: "forgejo",
        instanceUrl: "https://codeberg.org/",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await adapter.validateConnection();
      expect(requests[0].url).toBe("https://codeberg.org/api/v1/repos/me/site/contents/content/posts?ref=main");
      expect(requests[0].authorization).toBe("token pat");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("surfaces GitHub token permission failures during validation", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => new Response(JSON.stringify({ message: "Resource not accessible by personal access token" }), { status: 403, headers: { "content-type": "application/json" } });

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await expect(adapter.validateConnection()).rejects.toThrow("GitHub rejected the token or the token is missing Contents read/write permissions.");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("surfaces GitLab token permission failures during validation", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => new Response(JSON.stringify({ message: "403 Forbidden" }), { status: 403, headers: { "content-type": "application/json" } });

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await expect(adapter.validateConnection()).rejects.toThrow("GitLab rejected the token or the token is missing repository read/write permissions.");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("surfaces Forgejo token permission failures during validation", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => new Response(JSON.stringify({ message: "forbidden" }), { status: 403, headers: { "content-type": "application/json" } });

    try {
      const adapter = new ForgejoRepositoryAdapter({
        provider: "forgejo",
        instanceUrl: "https://codeberg.org",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await expect(adapter.validateConnection()).rejects.toThrow("Forgejo rejected the token or the token is missing write:repository permission.");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("does not overwrite existing GitHub posts when creating without a sha", async () => {
    const requests: Array<{ url: string; method: string }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", sha: "post-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await expect(adapter.savePost({ path: "content/posts/post.md", slug: "post", status: "draft", content: "Body" })).rejects.toThrow("content/posts/post.md already exists.");
      expect(requests.some((request) => request.method === "PUT")).toBe(false);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("does not overwrite existing GitLab posts when creating without a sha", async () => {
    const requests: Array<{ url: string; method: string }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method });
      if (url.includes("/repository/files/content%2Fposts%2Fpost.md")) return new Response(JSON.stringify({ file_path: "content/posts/post.md", file_name: "post.md", blob_id: "sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await expect(adapter.savePost({ path: "content/posts/post.md", slug: "post", status: "draft", content: "Body" })).rejects.toThrow("content/posts/post.md already exists.");
      expect(requests.some((request) => request.method === "POST" || request.method === "PUT")).toBe(false);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("sends equivalent frontmatter content through GitHub and GitLab save paths", async () => {
    const content = buildPostMarkdown({
      title: "Draft",
      slug: "draft",
      status: "draft",
      body: "Body",
      syndicationTargets: ["mastodon"],
      categoryTargets: ["Photography"],
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    let githubContent = "";
    let gitlabContent = "";
    const originalFetch = globalThis.fetch;

    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      if (url.includes("api.github.com")) {
        if (url.includes("/contents/content/posts/draft.md") && init.method !== "PUT") return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
        if (init.method === "PUT") {
          githubContent = decodeBase64(JSON.parse(String(init.body)).content);
          return new Response(JSON.stringify({ commit: { sha: "github-commit" } }), { status: 200, headers: { "content-type": "application/json" } });
        }
      }
      if (url.includes("gitlab.com")) {
        if (url.includes("/repository/files/content%2Fposts%2Fdraft.md") && init.method !== "POST") return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
        if (init.method === "POST") {
          gitlabContent = decodeBase64(JSON.parse(String(init.body)).content);
          return new Response(JSON.stringify({ id: "gitlab-commit" }), { status: 200, headers: { "content-type": "application/json" } });
        }
      }
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const github = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const gitlab = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await github.savePost({ path: "content/posts/draft.md", slug: "draft", status: "draft", content });
      await gitlab.savePost({ path: "content/posts/draft.md", slug: "draft", status: "draft", content });
      expect(githubContent).toBe(content);
      expect(gitlabContent).toBe(content);
      expect(githubContent).toContain("syndicate:\n  - mastodon");
      expect(githubContent).toContain("categories:\n  - Photography");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("loads GitHub Writer posts concurrently", async () => {
    let activeFileReads = 0;
    let maxActiveFileReads = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input) => {
      const url = String(input);
      if (url.includes("/git/trees/main?")) {
        return new Response(JSON.stringify({
          tree: [
            { type: "blob", path: "content/posts/older.md", sha: "older" },
            { type: "blob", path: "content/posts/newer.md", sha: "newer" }
          ]
        }), { status: 200, headers: { "content-type": "application/json" } });
      }
      activeFileReads += 1;
      maxActiveFileReads = Math.max(maxActiveFileReads, activeFileReads);
      await new Promise((resolve) => setTimeout(resolve, 10));
      activeFileReads -= 1;
      const newer = url.includes("/git/blobs/newer");
      return new Response(JSON.stringify({
        content: Buffer.from(`---\ntitle: ${newer ? "Newer" : "Older"}\ndate: ${newer ? "2026-05-12" : "2026-05-11"}\n---\n\nBody`).toString("base64")
      }), { status: 200, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const posts = await adapter.listPosts();
      expect(posts.map((post) => post.title)).toEqual(["Newer", "Older"]);
      expect(maxActiveFileReads).toBeGreaterThan(1);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("deletes GitHub Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", sha: "post-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response(JSON.stringify({ type: "file", path: "content/media/photo.jpg", sha: "photo-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main")) return new Response(JSON.stringify({ object: { sha: "parent-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/parent-sha")) return new Response(JSON.stringify({ sha: "parent-sha", tree: { sha: "tree-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "new-tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) return new Response(JSON.stringify({ sha: "new-commit-sha", html_url: "https://github.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/refs/heads/main")) return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.deletePost({ path: "content/posts/post.md", slug: "post", sha: "post-sha", mediaPaths: ["content/media/photo.jpg"] });
      expect(result.sha).toBe("new-commit-sha");
      const treeRequest = requests.find((request) => request.url.endsWith("/git/trees"));
      expect(treeRequest?.body).toMatchObject({
        base_tree: "tree-sha",
        tree: [
          { path: "content/posts/post.md", sha: null },
          { path: "content/media/photo.jpg", sha: null }
        ]
      });
      expect(requests.filter((request) => request.method === "DELETE")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("saves GitHub Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", sha: "post-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main")) return new Response(JSON.stringify({ object: { sha: "parent-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/parent-sha")) return new Response(JSON.stringify({ sha: "parent-sha", tree: { sha: "tree-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/blobs")) return new Response(JSON.stringify({ sha: `blob-${requests.filter((request) => request.url.endsWith("/git/blobs")).length}` }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "new-tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) return new Response(JSON.stringify({ sha: "new-commit-sha", html_url: "https://github.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/refs/heads/main")) return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "published",
        content: "---\ndate: 2026-05-11\n---\n\n![](/media/photo.jpg)",
        sha: "post-sha",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("new-commit-sha");
      const treeRequest = requests.find((request) => request.url.endsWith("/git/trees"));
      expect(treeRequest?.body).toMatchObject({
        base_tree: "tree-sha",
        tree: [
          { path: "content/posts/post.md" },
          { path: "content/media/photo.jpg" }
        ]
      });
      expect(requests.filter((request) => request.url.includes("/contents/") && request.method === "PUT")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("retries GitHub Writer media saves when the branch moved", async () => {
    let refUpdates = 0;
    let refReads = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      if (url.includes("/contents/content/posts/post.md")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main") && method === "GET") {
        refReads += 1;
        return new Response(JSON.stringify({ object: { sha: refReads === 1 ? "old-parent" : "new-parent" } }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/git/commits/old-parent")) return new Response(JSON.stringify({ sha: "old-parent", tree: { sha: "old-tree" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/new-parent")) return new Response(JSON.stringify({ sha: "new-parent", tree: { sha: "new-tree" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/blobs")) return new Response(JSON.stringify({ sha: "blob-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) return new Response(JSON.stringify({ sha: `commit-${refReads}` }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/refs/heads/main") && method === "PATCH") {
        refUpdates += 1;
        if (refUpdates === 1) return new Response(JSON.stringify({ message: "Update is not a fast forward" }), { status: 422, headers: { "content-type": "application/json" } });
        return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      }
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "draft",
        content: "Body\n\n![](/media/photo.jpg)",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("commit-2");
      expect(refUpdates).toBe(2);
      expect(refReads).toBe(2);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("reuses the latest GitHub branch head after a successful batch commit", async () => {
    let refReads = 0;
    const commits: string[] = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      if (url.includes("/contents/content/posts/")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main") && method === "GET") {
        refReads += 1;
        return new Response(JSON.stringify({ object: { sha: "initial-parent" } }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/git/commits/initial-parent")) return new Response(JSON.stringify({ sha: "initial-parent", tree: { sha: "initial-tree" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/commit-1")) return new Response(JSON.stringify({ sha: "commit-1", tree: { sha: "tree-1" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/blobs")) return new Response(JSON.stringify({ sha: "blob-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "new-tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) {
        const sha = `commit-${commits.length + 1}`;
        commits.push(sha);
        return new Response(JSON.stringify({ sha }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/git/refs/heads/main") && method === "PATCH") return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await adapter.savePost({
        path: "content/posts/one.md",
        slug: "one",
        status: "draft",
        content: "One",
        media: [{ path: "content/media/one.jpg", contentBase64: Buffer.from("one").toString("base64"), message: "Upload media" }]
      });
      await adapter.savePost({
        path: "content/posts/two.md",
        slug: "two",
        status: "draft",
        content: "Two",
        media: [{ path: "content/media/two.jpg", contentBase64: Buffer.from("two").toString("base64"), message: "Upload media" }]
      });
      expect(refReads).toBe(1);
      expect(commits).toEqual(["commit-1", "commit-2"]);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("deletes GitLab Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/repository/files/")) return new Response(JSON.stringify({ file_path: "file", file_name: "file", blob_id: "sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/repository/commits")) return new Response(JSON.stringify({ id: "new-commit-sha", web_url: "https://gitlab.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.deletePost({ path: "content/posts/post.md", slug: "post", mediaPaths: ["content/media/photo.jpg"] });
      expect(result.sha).toBe("new-commit-sha");
      const commitRequest = requests.find((request) => request.url.endsWith("/repository/commits"));
      expect(commitRequest?.body).toMatchObject({
        branch: "main",
        commit_message: "Delete post: post",
        actions: [
          { action: "delete", file_path: "content/posts/post.md" },
          { action: "delete", file_path: "content/media/photo.jpg" }
        ]
      });
      expect(requests.filter((request) => request.method === "DELETE")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("saves GitLab Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/repository/files/content%2Fposts%2Fpost.md")) return new Response(JSON.stringify({ file_path: "content/posts/post.md", file_name: "post.md", blob_id: "sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/repository/files/content%2Fmedia%2Fphoto.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.endsWith("/repository/commits")) return new Response(JSON.stringify({ id: "new-commit-sha", web_url: "https://gitlab.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "published",
        sha: "sha",
        content: "---\ndate: 2026-05-11\n---\n\n![](/media/photo.jpg)",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("new-commit-sha");
      const commitRequest = requests.find((request) => request.url.endsWith("/repository/commits"));
      expect(commitRequest?.body).toMatchObject({
        branch: "main",
        commit_message: "Publish post: post",
        actions: [
          { action: "update", file_path: "content/posts/post.md" },
          { action: "create", file_path: "content/media/photo.jpg" }
        ]
      });
      expect(requests.filter((request) => request.url.includes("/repository/files/") && ["POST", "PUT"].includes(request.method))).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("saves Forgejo Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", name: "post.md", sha: "post-sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.endsWith("/contents")) return new Response(JSON.stringify({ commit: { sha: "new-commit-sha", html_url: "https://forgejo.test/commit" } }), { status: 201, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new ForgejoRepositoryAdapter({
        provider: "forgejo",
        instanceUrl: "https://forgejo.test",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "published",
        sha: "post-sha",
        content: "---\ndate: 2026-05-11\n---\n\n![](/media/photo.jpg)",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("new-commit-sha");
      const commitRequest = requests.find((request) => request.url.endsWith("/contents") && request.method === "POST");
      expect(commitRequest?.body).toMatchObject({
        branch: "main",
        message: "Publish post: post",
        files: [
          { operation: "update", path: "content/posts/post.md", sha: "post-sha" },
          { operation: "create", path: "content/media/photo.jpg" }
        ]
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("deletes Forgejo Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", name: "post.md", sha: "post-sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response(JSON.stringify({ type: "file", path: "content/media/photo.jpg", name: "photo.jpg", sha: "photo-sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/contents")) return new Response(JSON.stringify({ commit: { sha: "new-commit-sha", html_url: "https://forgejo.test/commit" } }), { status: 201, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new ForgejoRepositoryAdapter({
        provider: "forgejo",
        instanceUrl: "https://forgejo.test",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.deletePost({ path: "content/posts/post.md", slug: "post", sha: "post-sha", mediaPaths: ["content/media/photo.jpg"] });
      expect(result.sha).toBe("new-commit-sha");
      const commitRequest = requests.find((request) => request.url.endsWith("/contents") && request.method === "POST");
      expect(commitRequest?.body).toMatchObject({
        branch: "main",
        message: "Delete post: post",
        files: [
          { operation: "delete", path: "content/posts/post.md", sha: "post-sha" },
          { operation: "delete", path: "content/media/photo.jpg", sha: "photo-sha" }
        ]
      });
      expect(requests.filter((request) => request.method === "DELETE")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

});
