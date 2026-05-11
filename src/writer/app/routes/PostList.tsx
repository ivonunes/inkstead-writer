import { useEffect, useRef, useState } from "react";
import type { RepositoryAdapter } from "../adapters/types.js";
import { Button } from "../components/Button.js";
import { PlusIcon } from "../components/icons.js";
import { navigate } from "../App.js";
import { formatPostDate, postListLabel, postStatusLabel, type PostSummary } from "../core/posts.js";

export function PostList({ adapter }: { adapter: RepositoryAdapter }): JSX.Element {
  const [posts, setPosts] = useState<PostSummary[]>([]);
  const [error, setError] = useState<string>();
  const [loading, setLoading] = useState(true);
  const [limit, setLimit] = useState(50);
  const [scrolled, setScrolled] = useState(false);
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const hasMore = posts.length >= limit;

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(undefined);
    adapter.listPosts({
      limit,
      onPosts(nextPosts, stillLoading) {
        if (!active) return;
        setPosts(nextPosts);
        setLoading(stillLoading);
      }
    })
      .then((nextPosts) => {
        if (!active) return;
        setPosts(nextPosts);
      })
      .catch((err: Error) => {
        if (!active) return;
        setError(err.message);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [adapter, limit]);

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

  return (
    <main className="shell">
      <header className={`topbar writer-nav ${scrolled ? "is-scrolled" : ""}`}>
        <h1>Posts</h1>
        <Button icon={<PlusIcon />} aria-label="New post" onClick={() => navigate("/new")}>New Post</Button>
      </header>
      {error ? <p className="error">{error}</p> : null}
      <section className="post-list">
        {loading && posts.length === 0 ? <p className="muted">Loading posts...</p> : null}
        {posts.map((post) => {
          const date = formatPostDate(post.date ?? post.updatedAt);
          return (
            <button className="post-row" key={post.path} onClick={() => navigate(`/edit/${encodeURIComponent(post.path)}`)}>
              <span>{postListLabel(post)}</span>
              <small>{postStatusLabel(post.status)}{date ? ` · ${date}` : ""}</small>
            </button>
          );
        })}
        {posts.length > 0 ? <div ref={loadMoreRef} className="load-more">{loading ? "Loading more posts..." : hasMore ? "Load older posts" : ""}</div> : null}
        {!loading && posts.length === 0 && !error ? <p className="muted">No posts yet.</p> : null}
      </section>
    </main>
  );
}
