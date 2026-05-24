import { describe, expect, it } from "vitest";
import { shouldRedirectConnectToPosts } from "../src/writer/app/App.js";
import { clearLocalWriterDraft, loadLocalWriterDraft, localDraftIdentifier, localDraftKey, saveLocalWriterDraft } from "../src/writer/app/core/local-drafts.js";
import { forgetToken, getRememberedToken, rememberToken } from "../src/writer/app/core/session.js";
import type { WriterPublicConfig } from "../src/writer/app/core/config.js";

const remoteConfig: WriterPublicConfig = {
  provider: "github",
  owner: "me",
  repo: "site",
  branch: "main",
  postsPath: "content/posts",
  mediaPath: "content/media"
};

const localConfig: WriterPublicConfig = {
  provider: "local",
  postsPath: "content/posts",
  mediaPath: "content/media"
};

function withLocalStorage<T>(storage: Pick<Storage, "getItem" | "setItem" | "removeItem">, run: () => T): T {
  const original = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  Object.defineProperty(globalThis, "localStorage", { configurable: true, value: storage });
  try {
    return run();
  } finally {
    if (original) Object.defineProperty(globalThis, "localStorage", original);
    else delete (globalThis as { localStorage?: Storage }).localStorage;
  }
}

describe("writer app", () => {
  it("redirects remembered-token and local-provider launches away from the connect route", () => {
    expect(shouldRedirectConnectToPosts(remoteConfig, "pat", { name: "connect" })).toBe(true);
    expect(shouldRedirectConnectToPosts(remoteConfig, undefined, { name: "connect" })).toBe(false);
    expect(shouldRedirectConnectToPosts(localConfig, undefined, { name: "connect" })).toBe(true);
    expect(shouldRedirectConnectToPosts(remoteConfig, "pat", { name: "posts" })).toBe(false);
  });

  it("persists and clears remembered Writer tokens when storage is available", () => {
    const values = new Map<string, string>();
    withLocalStorage({
      getItem: (key) => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, value),
      removeItem: (key) => values.delete(key)
    }, () => {
      rememberToken("pat");
      expect(getRememberedToken()).toBe("pat");
      forgetToken();
      expect(getRememberedToken()).toBeUndefined();
    });
  });

  it("does not throw when browser storage is unavailable", () => {
    withLocalStorage({
      getItem: () => { throw new Error("blocked"); },
      setItem: () => { throw new Error("blocked"); },
      removeItem: () => { throw new Error("blocked"); }
    }, () => {
      expect(getRememberedToken()).toBeUndefined();
      expect(() => rememberToken("pat")).not.toThrow();
      expect(() => forgetToken()).not.toThrow();
    });
  });

  it("stores local Writer drafts by site and post identifier", () => {
    const values = new Map<string, string>();
    withLocalStorage({
      getItem: (key) => values.get(key) ?? null,
      setItem: (key, value) => values.set(key, value),
      removeItem: (key) => values.delete(key)
    }, () => {
      expect(localDraftIdentifier(undefined)).toBe("__new__");
      const key = localDraftKey(remoteConfig, "content/posts/post.md");
      expect(key).toContain("github::me:site:main:content/posts:content/posts/post.md");
      saveLocalWriterDraft(remoteConfig, "content/posts/post.md", {
        title: "Draft",
        body: "Body",
        syndicationTargets: ["mastodon"],
        categoryTargets: ["Photography"]
      });
      expect(loadLocalWriterDraft(remoteConfig, "content/posts/post.md")).toMatchObject({
        title: "Draft",
        body: "Body",
        syndicationTargets: ["mastodon"],
        categoryTargets: ["Photography"]
      });
      clearLocalWriterDraft(remoteConfig, "content/posts/post.md");
      expect(loadLocalWriterDraft(remoteConfig, "content/posts/post.md")).toBeUndefined();
    });
  });
});
