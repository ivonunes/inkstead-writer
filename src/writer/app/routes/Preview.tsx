import { useEffect, useState } from "react";
import type { RepositoryAdapter } from "../adapters/types.js";
import { Button } from "../components/Button.js";
import { ArrowLeftIcon } from "../components/icons.js";
import { parsePostMarkdown } from "../core/frontmatter.js";
import { renderPreviewMarkdown } from "../core/markdown.js";
import { navigate } from "../App.js";

export function previewTitle(value: string | undefined): string | undefined {
  const title = value?.trim();
  return title || undefined;
}

export function Preview({ adapter, postPath }: { adapter: RepositoryAdapter; postPath: string }): JSX.Element {
  const [html, setHtml] = useState("");
  const [title, setTitle] = useState<string>();
  const [error, setError] = useState<string>();

  useEffect(() => {
    adapter.readPost(postPath).then((post) => {
      const parsed = parsePostMarkdown(post.content);
      setTitle(previewTitle(parsed.frontmatter.title));
      setHtml(renderPreviewMarkdown(parsed.body));
    }).catch((err: Error) => setError(err.message));
  }, [adapter, postPath]);

  return (
    <main className="shell preview-shell">
      <header className="topbar preview-bar">
        <Button icon={<ArrowLeftIcon />} aria-label="Back" onClick={() => navigate(`/edit/${encodeURIComponent(postPath)}`)}>Back</Button>
      </header>
      {error ? <p className="error">{error}</p> : (
        <article className="preview">
          {title ? <h1>{title}</h1> : null}
          <div dangerouslySetInnerHTML={{ __html: html }} />
        </article>
      )}
    </main>
  );
}
