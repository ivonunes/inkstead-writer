import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { createRepositoryAdapter } from "./adapters/factory.js";
import type { RepositoryAdapter } from "./adapters/types.js";
import { loadWriterConfig, type WriterPublicConfig } from "./core/config.js";
import { isPostFileCacheStale, removePostFile, removePostSummary, upsertPostFile, upsertPostSummary, type CachedPostFile } from "./core/post-cache.js";
import type { PostFile, PostSummary } from "./core/posts.js";
import { getRememberedToken } from "./core/session.js";
import { ConnectRepository } from "./routes/ConnectRepository.js";
import { Editor } from "./routes/Editor.js";
import { PostList } from "./routes/PostList.js";
import { Preview } from "./routes/Preview.js";

type Route =
  | { name: "connect" }
  | { name: "posts" }
  | { name: "new" }
  | { name: "edit"; path: string }
  | { name: "preview"; path: string };

type TransitionDirection = "forward" | "back";
type ToastTone = "success" | "error" | "info";

interface ToastMessage {
  message: string;
  tone: ToastTone;
  visible: boolean;
}

const routeDepth: Record<Route["name"], number> = {
  connect: 0,
  posts: 1,
  new: 2,
  edit: 2,
  preview: 3
};

function parseRoute(): Route {
  const hash = window.location.hash.replace(/^#/, "") || "/connect";
  const parts = hash.split("/");
  if (hash === "/posts") return { name: "posts" };
  if (hash === "/new") return { name: "new" };
  if (parts[1] === "edit" && parts[2]) return { name: "edit", path: decodeURIComponent(parts.slice(2).join("/")) };
  if (parts[1] === "preview" && parts[2]) return { name: "preview", path: decodeURIComponent(parts.slice(2).join("/")) };
  return { name: "connect" };
}

export function navigate(route: string): void {
  window.location.hash = route;
}

export function shouldRedirectConnectToPosts(config: WriterPublicConfig | undefined, token: string | undefined, route: Pick<Route, "name">): boolean {
  if (route.name !== "connect" || !config) return false;
  return config.provider === "local" || Boolean(token);
}

export function App(): JSX.Element {
  const [config, setConfig] = useState<WriterPublicConfig>();
  const [token, setToken] = useState<string | undefined>(() => getRememberedToken());
  const [route, setRoute] = useState<Route>(parseRoute);
  const [error, setError] = useState<string>();
  const [postSummaries, setPostSummaries] = useState<PostSummary[]>();
  const [postSummariesLoadedAt, setPostSummariesLoadedAt] = useState<number>();
  const [postFiles, setPostFiles] = useState<Record<string, CachedPostFile>>({});
  const [toast, setToast] = useState<ToastMessage>();
  const [online, setOnline] = useState(() => typeof navigator === "undefined" ? true : navigator.onLine);
  const [direction, setDirection] = useState<TransitionDirection>("forward");
  const previousRoute = useRef(route);
  const hasNavigated = useRef(false);
  const prefetchingPosts = useRef<Set<string>>(new Set());
  const toastDismissTimer = useRef<number>();
  const toastRemoveTimer = useRef<number>();

  useEffect(() => {
    loadWriterConfig().then(setConfig).catch((err: Error) => setError(err.message));
    const onHashChange = () => {
      const nextRoute = parseRoute();
      setDirection(routeDepth[nextRoute.name] < routeDepth[previousRoute.current.name] ? "back" : "forward");
      previousRoute.current = nextRoute;
      hasNavigated.current = true;
      setRoute(nextRoute);
    };
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  useEffect(() => {
    const onOnline = () => setOnline(true);
    const onOffline = () => setOnline(false);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, []);

  useEffect(() => {
    if (!toast) return undefined;
    toastDismissTimer.current = window.setTimeout(() => {
      setToast((current) => current ? { ...current, visible: false } : undefined);
      toastRemoveTimer.current = window.setTimeout(() => setToast(undefined), 260);
    }, 3000);
    return () => {
      if (toastDismissTimer.current !== undefined) window.clearTimeout(toastDismissTimer.current);
      if (toastRemoveTimer.current !== undefined) window.clearTimeout(toastRemoveTimer.current);
    };
  }, [toast]);

  const adapter = useMemo<RepositoryAdapter | undefined>(() => {
    if (!config) return undefined;
    if (config.provider !== "local" && !token) return undefined;
    return createRepositoryAdapter(config, token);
  }, [config, token]);

  useEffect(() => {
    if (shouldRedirectConnectToPosts(config, token, route)) navigate("/posts");
  }, [config, route.name, token]);

  function showToast(message: string, tone: ToastTone = "info"): void {
    if (toastDismissTimer.current !== undefined) window.clearTimeout(toastDismissTimer.current);
    if (toastRemoveTimer.current !== undefined) window.clearTimeout(toastRemoveTimer.current);
    setToast({ message, tone, visible: true });
  }

  function cachePostFile(post: PostFile): void {
    setPostFiles((current) => upsertPostFile(current, post));
    setPostSummaries((current) => upsertPostSummary(current, post));
    setPostSummariesLoadedAt(Date.now());
  }

  function removeCachedPost(path: string): void {
    setPostFiles((current) => removePostFile(current, path));
    setPostSummaries((current) => removePostSummary(current, path));
    setPostSummariesLoadedAt(Date.now());
  }

  function prefetchPost(path: string): void {
    if (!adapter || prefetchingPosts.current.has(path) || !isPostFileCacheStale(postFiles[path])) return;
    prefetchingPosts.current.add(path);
    adapter.readPost(path)
      .then(cachePostFile)
      .catch(() => undefined)
      .finally(() => prefetchingPosts.current.delete(path));
  }

  function screen(content: ReactNode): JSX.Element {
    return (
      <>
        <div key={`${route.name}${"path" in route ? route.path : ""}`} className={`route-screen ${hasNavigated.current ? `route-${direction}` : "route-initial"}`}>{content}</div>
        {toast ? <div className={`toast toast-${toast.tone} ${toast.visible ? "is-visible" : ""}`} role="status">{toast.message}</div> : null}
      </>
    );
  }

  if (error) return screen(<main className="shell"><p className="error">{error}</p></main>);
  if (!config) return screen(<main className="shell"><p>Loading Writer...</p></main>);
  if (!adapter || route.name === "connect") {
    return screen(<ConnectRepository config={config} onConnected={(nextToken) => {
      setToken(nextToken);
      navigate("/posts");
    }} />);
  }
  const readOnly = config.provider !== "local" && !online;

  if (route.name === "new") return screen(<Editor
    adapter={adapter}
    config={config}
    readOnly={readOnly}
    onPostSaved={cachePostFile}
    onPostLoaded={cachePostFile}
    onToast={showToast}
  />);
  if (route.name === "edit") return screen(<Editor
    adapter={adapter}
    config={config}
    postPath={route.path}
    initialPost={postSummaries?.find((post) => post.path === route.path)}
    initialFile={postFiles[route.path]?.post}
    readOnly={readOnly}
    onPostSaved={cachePostFile}
    onPostLoaded={cachePostFile}
    onPostDeleted={removeCachedPost}
    onToast={showToast}
  />);
  if (route.name === "preview") return screen(<Preview adapter={adapter} postPath={route.path} />);
  return screen(<PostList
    adapter={adapter}
    initialPosts={postSummaries}
    initialPostsLoadedAt={postSummariesLoadedAt}
    readOnly={readOnly}
    onPrefetchPost={prefetchPost}
    onToast={showToast}
    onPostsChange={(posts) => {
      setPostSummaries(posts);
      setPostSummariesLoadedAt(Date.now());
    }}
  />);
}
