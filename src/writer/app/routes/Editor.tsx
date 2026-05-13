import { useEffect, useMemo, useRef, useState } from "react";
import type { RepositoryAdapter } from "../adapters/types.js";
import { Button } from "../components/Button.js";
import { Dialog } from "../components/Dialog.js";
import { ArrowLeftIcon, EyeIcon, ImageIcon, SaveIcon, TrashIcon, UploadIcon } from "../components/icons.js";
import { StatusBar } from "../components/StatusBar.js";
import type { SyndicationProvider, WriterPublicConfig } from "../core/config.js";
import { buildPostMarkdown, filenameSlug, postPath as buildPostPath, slugForNewPost, type PostStatus } from "../core/posts.js";
import { fileToBase64, markdownMediaReference, maxMediaUploadBytes, mediaAssetPath, referencedMediaPaths, uniqueAssetFilename, type PendingAsset } from "../core/assets.js";
import { parsePostMarkdown } from "../core/frontmatter.js";
import { navigate } from "../App.js";

function isExistingPostError(error: unknown): boolean {
  return error instanceof Error && /already exists\.$/.test(error.message);
}

function syndicationTargetsFromFrontmatter(value: unknown, fallback: SyndicationProvider[]): SyndicationProvider[] {
  if (!Array.isArray(value)) return fallback;
  return value.filter((item): item is SyndicationProvider => fallback.includes(item as SyndicationProvider));
}

function categoriesFromFrontmatter(value: unknown, configuredCategories: string[]): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && configuredCategories.includes(item));
}

function unmanagedCategoriesFromFrontmatter(value: unknown, configuredCategories: string[]): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && !configuredCategories.includes(item));
}

export function Editor({ adapter, config, postPath }: { adapter: RepositoryAdapter; config: WriterPublicConfig; postPath?: string }): JSX.Element {
  const configuredSyndicationProviders = config.syndicationProviders ?? [];
  const configuredCategories = config.categories ?? [];
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [syndicationTargets, setSyndicationTargets] = useState<SyndicationProvider[]>(configuredSyndicationProviders);
  const [categoryTargets, setCategoryTargets] = useState<string[]>([]);
  const [unmanagedCategoryTargets, setUnmanagedCategoryTargets] = useState<string[]>([]);
  const [sha, setSha] = useState<string>();
  const [path, setPath] = useState(postPath);
  const [slug, setSlug] = useState("");
  const [originalMarkdown, setOriginalMarkdown] = useState<string>();
  const [postStatus, setPostStatus] = useState<PostStatus>("draft");
  const [status, setStatus] = useState("Saved");
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showDiscardDialog, setShowDiscardDialog] = useState(false);
  const pendingAssets = useRef<PendingAsset[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const currentSlug = useMemo(() => slug || slugForNewPost(title, body), [slug, title, body]);
  const hasContent = title.trim().length > 0 || body.trim().length > 0 || pendingAssets.current.length > 0;
  const hasUnsavedChanges = status === "Unsaved" && Boolean(path || hasContent);
  const canEditSyndicationTargets = postStatus === "draft";
  const showSyndicationTargets = canEditSyndicationTargets && configuredSyndicationProviders.length > 0;
  const showCategoryTargets = configuredCategories.length > 0;

  useEffect(() => {
    if (!postPath) {
      setStatus("Unsaved");
      return;
    }
    adapter.readPost(postPath).then((post) => {
      const parsed = parsePostMarkdown(post.content);
      setTitle(typeof parsed.frontmatter.title === "string" ? parsed.frontmatter.title : "");
      setBody(parsed.body);
      setSha(post.sha);
      setPath(post.path);
      setSlug(post.slug || filenameSlug(post.path));
      setOriginalMarkdown(post.content);
      setPostStatus(post.status);
      setSyndicationTargets(syndicationTargetsFromFrontmatter(parsed.frontmatter.syndicate, configuredSyndicationProviders));
      setCategoryTargets(categoriesFromFrontmatter(parsed.frontmatter.categories, configuredCategories));
      setUnmanagedCategoryTargets(unmanagedCategoriesFromFrontmatter(parsed.frontmatter.categories, configuredCategories));
      setStatus("Saved");
    }).catch((err: Error) => setError(err.message));
  }, [adapter, postPath]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void save("draft");
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  });

  function insertAtCursor(markdown: string): void {
    const textarea = textareaRef.current;
    if (!textarea) {
      setBody((value) => `${value}\n${markdown}`);
      return;
    }
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    setBody((value) => `${value.slice(0, start)}${markdown}${value.slice(end)}`);
    requestAnimationFrame(() => {
      textarea.focus();
      textarea.selectionStart = textarea.selectionEnd = start + markdown.length;
    });
  }

  function toggleSyndicationTarget(provider: SyndicationProvider): void {
    setSyndicationTargets((current) => current.includes(provider)
      ? current.filter((item) => item !== provider)
      : [...current, provider]);
    setStatus("Unsaved");
  }

  function toggleCategoryTarget(category: string): void {
    setCategoryTargets((current) => current.includes(category)
      ? current.filter((item) => item !== category)
      : [...current, category]);
    setStatus("Unsaved");
  }

  async function addFiles(files: FileList | File[]): Promise<void> {
    const imageFiles = Array.from(files).filter((file) => file.type.startsWith("image/"));
    if (imageFiles.length === 0) return;
    const oversized = imageFiles.find((file) => file.size > maxMediaUploadBytes);
    if (oversized) {
      setError(`${oversized.name} is too large to upload. Keep individual images under 25 MB.`);
      return;
    }
    setBusy(true);
    setStatus(imageFiles.length === 1 ? "Preparing image..." : "Preparing images...");
    setError(undefined);
    try {
      const existing = await adapter.listAssets(config.mediaPath);
      const reserved = new Set([
        ...existing.map((asset) => asset.name),
        ...pendingAssets.current.map((asset) => asset.path.split("/").pop() ?? "")
      ]);
      for (const file of imageFiles) {
        const filename = uniqueAssetFilename(file.name, reserved);
        reserved.add(filename);
        const path = mediaAssetPath(config.mediaPath, filename);
        const reference = markdownMediaReference(config.mediaPath, filename);
        pendingAssets.current.push({ file, path, markdownReference: reference });
        insertAtCursor(`![${file.name}](${reference})`);
      }
      setStatus(imageFiles.length === 1 ? "Image ready to upload." : "Images ready to upload.");
    } catch (err) {
      setStatus("Unsaved");
      setError(err instanceof Error ? err.message : "Could not prepare images.");
    } finally {
      setBusy(false);
    }
  }

  async function save(nextStatus: "draft" | "published", options: { updateDate?: boolean } = {}): Promise<void> {
    if (busy) return;
    setBusy(true);
    setStatus(pendingAssets.current.length > 0 ? "Uploading media..." : nextStatus === "published" ? "Publishing..." : "Saving...");
    setError(undefined);
    try {
      const media = await Promise.all(pendingAssets.current.map(async (asset) => ({
        path: asset.path,
        contentBase64: await fileToBase64(asset.file),
        message: `Upload media: ${asset.path.split("/").pop() ?? "image"}`
      })));
      const baseSlug = path ? currentSlug : slugForNewPost(title, body);
      let nextSlug = baseSlug;
      let nextPath = path ?? buildPostPath(config.postsPath, nextSlug);
      let saved = false;
      for (let attempt = 1; attempt <= 20 && !saved; attempt += 1) {
        nextSlug = path || attempt === 1 ? baseSlug : `${baseSlug}-${attempt}`;
        nextPath = path ?? buildPostPath(config.postsPath, nextSlug);
        const content = buildPostMarkdown({
          title,
          slug: nextSlug,
          status: nextStatus,
          body,
          existingMarkdown: originalMarkdown,
          updateDate: options.updateDate,
          syndicationTargets: canEditSyndicationTargets ? syndicationTargets : undefined,
          categoryTargets: showCategoryTargets ? [...unmanagedCategoryTargets, ...categoryTargets] : undefined
        });
        try {
          await adapter.savePost({ path: nextPath, slug: nextSlug, status: nextStatus, content, sha, media });
          saved = true;
        } catch (err) {
          if (path || !isExistingPostError(err) || attempt === 20) throw err;
        }
      }
      pendingAssets.current = [];
      const savedPost = await adapter.readPost(nextPath);
      setSha(savedPost.sha);
      setOriginalMarkdown(savedPost.content);
      setPostStatus(savedPost.status);
      setPath(nextPath);
      setSlug(nextSlug);
      setStatus(nextStatus === "published" ? "Published." : "Saved.");
    } catch (err) {
      setStatus("Unsaved");
      setError(err instanceof Error ? err.message : "Save failed.");
    } finally {
      setBusy(false);
    }
  }

  async function remove(): Promise<void> {
    if (!path || busy) return;
    setBusy(true);
    setStatus("Deleting...");
    setError(undefined);
    try {
      await adapter.deletePost({ path, slug: currentSlug, sha, mediaPaths: referencedMediaPaths(originalMarkdown ?? body, config.mediaPath) });
      setStatus("Deleted.");
      navigate("/posts");
    } catch (err) {
      setStatus("Unsaved");
      setError(err instanceof Error ? err.message : "Delete failed.");
      setBusy(false);
    }
  }

  function back(): void {
    if (hasUnsavedChanges) {
      setShowDiscardDialog(true);
      return;
    }
    navigate("/posts");
  }

  return (
    <main className="editor">
      <header className="editor-bar">
        <Button icon={<ArrowLeftIcon />} aria-label="Back" onClick={back} disabled={busy}>Back</Button>
        <div className="editor-actions">
          {path ? <Button icon={<TrashIcon />} aria-label="Delete" className="danger" onClick={() => setShowDeleteDialog(true)} disabled={busy}>Delete</Button> : null}
          <Button icon={<ImageIcon />} aria-label="Insert image" onClick={() => fileInputRef.current?.click()} disabled={busy}>Insert image</Button>
          {postStatus === "published" ? (
            <Button icon={<SaveIcon />} aria-label={busy ? "Saving" : "Save"} onClick={() => save("published")} disabled={busy}>Save</Button>
          ) : (
            <>
              <Button icon={<SaveIcon />} aria-label={busy ? "Saving draft" : "Save draft"} onClick={() => save("draft")} disabled={busy}>Save draft</Button>
              <Button icon={<UploadIcon />} aria-label={busy ? "Publishing" : "Publish"} onClick={() => save("published", { updateDate: true })} disabled={busy}>Publish</Button>
            </>
          )}
          {path ? <Button icon={<EyeIcon />} aria-label="Preview" onClick={() => navigate(`/preview/${encodeURIComponent(path)}`)} disabled={busy}>Preview</Button> : null}
        </div>
      </header>
      {showDeleteDialog ? (
        <div className="modal-backdrop" role="presentation">
          <Dialog>
            <h2>Delete post?</h2>
            <p className="muted">This action cannot be undone.</p>
            <div className="dialog-actions">
              <Button onClick={() => setShowDeleteDialog(false)} disabled={busy}>Cancel</Button>
              <Button icon={<TrashIcon />} className="danger" onClick={remove} disabled={busy}>{busy ? "Deleting" : "Delete"}</Button>
            </div>
          </Dialog>
        </div>
      ) : null}
      {showDiscardDialog ? (
        <div className="modal-backdrop" role="presentation">
          <Dialog>
            <h2>Discard changes?</h2>
            <p className="muted">You have unsaved changes. Going back will lose them.</p>
            <div className="dialog-actions">
              <Button onClick={() => setShowDiscardDialog(false)}>Cancel</Button>
              <Button className="danger" onClick={() => navigate("/posts")}>Discard</Button>
            </div>
          </Dialog>
        </div>
      ) : null}
      <input
        ref={fileInputRef}
        className="hidden-file-input"
        type="file"
        accept="image/*"
        multiple
        onChange={(event) => {
          if (event.target.files && !busy) void addFiles(event.target.files);
          event.target.value = "";
        }}
      />
      <input className="title-input" value={title} onChange={(event) => {
        setTitle(event.target.value);
        setStatus("Unsaved");
      }} placeholder="Title (optional)" />
      {showSyndicationTargets ? (
        <section className="frontmatter-targets" aria-label="Syndication targets">
          <p>Syndicate to</p>
          <div>
            {configuredSyndicationProviders.map((provider) => (
              <label key={provider} className="target-chip">
                <input
                  type="checkbox"
                  checked={syndicationTargets.includes(provider)}
                  onChange={() => toggleSyndicationTarget(provider)}
                />
                <span>{provider}</span>
              </label>
            ))}
          </div>
        </section>
      ) : null}
      {showCategoryTargets ? (
        <section className="frontmatter-targets" aria-label="Categories">
          <p>Categories</p>
          <div>
            {configuredCategories.map((category) => (
              <label key={category} className="target-chip">
                <input
                  type="checkbox"
                  checked={categoryTargets.includes(category)}
                  onChange={() => toggleCategoryTarget(category)}
                />
                <span>{category}</span>
              </label>
            ))}
          </div>
        </section>
      ) : null}
      <textarea
        ref={textareaRef}
        className="markdown-editor"
        value={body}
        onChange={(event) => {
          setBody(event.target.value);
          setStatus("Unsaved");
        }}
        onPaste={(event) => {
          if (!busy) void addFiles(event.clipboardData.files);
        }}
        onDrop={(event) => {
          event.preventDefault();
          if (!busy) void addFiles(event.dataTransfer.files);
        }}
        onDragOver={(event) => event.preventDefault()}
        placeholder="Write..."
      />
      <StatusBar status={status} error={error} busy={busy} />
    </main>
  );
}
