import { type TouchEvent, useEffect, useRef, useState } from "react";
import type { RepositoryAdapter } from "../adapters/types.js";
import { Button } from "../components/Button.js";
import { PlusIcon } from "../components/icons.js";
import { navigate } from "../App.js";
import { isPostSummaryCacheStale } from "../core/post-cache.js";
import { formatPostDate, postListLabel, postStatusLabel, type PostSummary } from "../core/posts.js";

export function PostList({ adapter, initialPosts, initialPostsLoadedAt, readOnly = false, onPrefetchPost, onPostsChange, onToast }: {
  adapter: RepositoryAdapter;
  initialPosts?: PostSummary[];
  initialPostsLoadedAt?: number;
  readOnly?: boolean;
  onPrefetchPost?: (path: string) => void;
  onPostsChange?: (posts: PostSummary[]) => void;
  onToast?: (message: string, tone?: "success" | "error" | "info") => void;
}): JSX.Element {
  const [posts, setPosts] = useState<PostSummary[]>(initialPosts ?? []);
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(!initialPosts);
  const [limit, setLimit] = useState(50);
  const [scrolled, setScrolled] = useState(false);
  const [refreshNonce, setRefreshNonce] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const [pullDistance, setPullDistance] = useState(0);
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const pullStartY = useRef<number>();
  const hasMore = posts.length >= limit;
  const pullThreshold = 68;

  useEffect(() => {
    let active = true;
    setLoading(posts.length === 0);
    setError(undefined);
    adapter.listPosts({
      limit,
      onPosts(nextPosts, stillLoading) {
        if (!active) return;
        setPosts(nextPosts);
        onPostsChange?.(nextPosts);
        setLoading(stillLoading);
      }
    })
      .then((nextPosts) => {
        if (!active) return;
        setPosts(nextPosts);
        onPostsChange?.(nextPosts);
        if (refreshNonce > 0) onToast?.("Posts refreshed.", "success");
      })
      .catch((err: Error) => {
        if (!active) return;
        setError(err.message);
        onToast?.("Could not refresh posts.", "error");
      })
      .finally(() => {
        if (active) {
          setLoading(false);
          setRefreshing(false);
          setPullDistance(0);
        }
      });
    return () => {
      active = false;
    };
  }, [adapter, limit, refreshNonce]);

  useEffect(() => {
    const refreshIfStale = () => {
      if (document.visibilityState === "visible" && isPostSummaryCacheStale(initialPostsLoadedAt)) {
        setRefreshNonce((value) => value + 1);
      }
    };
    document.addEventListener("visibilitychange", refreshIfStale);
    window.addEventListener("focus", refreshIfStale);
    return () => {
      document.removeEventListener("visibilitychange", refreshIfStale);
      window.removeEventListener("focus", refreshIfStale);
    };
  }, [initialPostsLoadedAt]);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 14);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    const target = loadMoreRef.current;
    if (!target || !hasMore) return undefined;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) setLimit((current) => current + 50);
    }, { rootMargin: "300px 0px" });
    observer.observe(target);
    return () => observer.disconnect();
  }, [hasMore, posts.length]);

  function refreshPosts(): void {
    if (readOnly || refreshing) return;
    setRefreshing(true);
    setLoading(posts.length === 0);
    setRefreshNonce((value) => value + 1);
  }

  function onTouchStart(event: TouchEvent<HTMLElement>): void {
    if (readOnly || loading || refreshing || window.scrollY > 0) return;
    pullStartY.current = event.touches[0]?.clientY;
  }

  function onTouchMove(event: TouchEvent<HTMLElement>): void {
    if (pullStartY.current === undefined || window.scrollY > 0) return;
    const y = event.touches[0]?.clientY;
    if (y === undefined) return;
    const distance = y - pullStartY.current;
    if (distance <= 0) {
      setPullDistance(0);
      return;
    }
    setPullDistance(Math.min(92, distance * 0.55));
  }

  function onTouchEnd(): void {
    if (pullDistance >= pullThreshold) refreshPosts();
    else setPullDistance(0);
    pullStartY.current = undefined;
  }

  return (
    <main className="shell" onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd} onTouchCancel={onTouchEnd}>
      <header className={`topbar writer-nav ${scrolled ? "is-scrolled" : ""}`}>
        <h1>Posts</h1>
        <div className="topbar-actions">
          <Button icon={<PlusIcon />} aria-label="New post" onClick={() => navigate("/new")} disabled={readOnly}>New Post</Button>
        </div>
      </header>
      {readOnly ? <p className="notice">You are offline. Cached posts remain available, but editing is paused until the connection returns.</p> : null}
      {error ? <p className="error">{error}</p> : null}
      <div
        className={`pull-refresh ${refreshing || pullDistance > 0 ? "is-visible" : ""} ${refreshing || pullDistance >= pullThreshold ? "is-ready" : ""}`}
        aria-hidden="true"
        style={{ height: refreshing ? 44 : pullDistance }}
      >
        <span className="brand-mark" />
      </div>
      <section className="post-list">
        {loading && posts.length === 0 ? (
          <div className="post-skeletons" aria-label="Loading posts">
            <p className="muted loading-row"><span className="spinner" aria-hidden="true" />Loading posts...</p>
            <span className="post-skeleton" />
            <span className="post-skeleton" />
            <span className="post-skeleton" />
          </div>
        ) : null}
        {posts.map((post) => {
          const date = formatPostDate(post.date ?? post.updatedAt);
          return (
            <button
              className="post-row"
              key={post.path}
              onClick={() => navigate(`/edit/${encodeURIComponent(post.path)}`)}
              onPointerEnter={() => onPrefetchPost?.(post.path)}
              onFocus={() => onPrefetchPost?.(post.path)}
              onTouchStart={() => onPrefetchPost?.(post.path)}
            >
              <span>{postListLabel(post)}</span>
              <small>{postStatusLabel(post.status)}{date ? ` · ${date}` : ""}</small>
            </button>
          );
        })}
        {posts.length > 0 ? (
          <div ref={loadMoreRef} className="load-more">
            {loading ? <span><span className="spinner" aria-hidden="true" />Loading more posts...</span> : hasMore ? "Load older posts" : ""}
          </div>
        ) : null}
        {!loading && posts.length === 0 && !error ? (
          <div className="empty-state">
            <span className="brand-mark" aria-hidden="true" />
            <p className="muted">No posts yet.</p>
          </div>
        ) : null}
      </section>
    </main>
  );
}
