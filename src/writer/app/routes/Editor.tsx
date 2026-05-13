import { useEffect, useMemo, useRef, useState } from "react";
import type { RepositoryAdapter } from "../adapters/types.js";
import { Button } from "../components/Button.js";
import { Dialog } from "../components/Dialog.js";
import { ArrowLeftIcon, EyeIcon, ImageIcon, RefreshIcon, SaveIcon, TrashIcon, UploadIcon } from "../components/icons.js";
import { StatusBar } from "../components/StatusBar.js";
import type { SyndicationProvider, WriterPublicConfig } from "../core/config.js";
import { categoriesFromFrontmatter, shouldShowCategoryTargets, shouldShowSyndicationTargets, syndicationTargetsFromFrontmatter, unmanagedCategoriesFromFrontmatter } from "../core/editor-state.js";
import { buildPostMarkdown, filenameSlug, postPath as buildPostPath, slugForNewPost, summarizePost, type PostFile, type PostStatus, type PostSummary } from "../core/posts.js";
import { fileToBase64, markdownMediaReference, maxMediaUploadBytes, mediaAssetPath, referencedMediaPaths, uniqueAssetFilename, type PendingAsset } from "../core/assets.js";
import { parsePostMarkdown } from "../core/frontmatter.js";
import { clearLocalWriterDraft, loadLocalWriterDraft, localDraftIdentifier, saveLocalWriterDraft } from "../core/local-drafts.js";
import { postFileCacheMaxAge } from "../core/post-cache.js";
import { navigate } from "../App.js";

function isExistingPostError(error: unknown): boolean {
  return error instanceof Error && /already exists\.$/.test(error.message);
}

export function Editor({ adapter, config, postPath, initialPost, initialFile, readOnly = false, onPostSaved, onPostLoaded, onPostDeleted, onToast }: {
  adapter: RepositoryAdapter;
  config: WriterPublicConfig;
  postPath?: string;
  initialPost?: PostSummary;
  initialFile?: PostFile;
  readOnly?: boolean;
  onPostSaved?: (post: PostFile) => void;
  onPostLoaded?: (post: PostFile) => void;
  onPostDeleted?: (path: string) => void;
  onToast?: (message: string, tone?: "success" | "error" | "info") => void;
}): JSX.Element {
  const configuredSyndicationProviders = config.syndicationProviders ?? [];
  const configuredCategories = config.categories ?? [];
  const initialParsed = initialFile ? parsePostMarkdown(initialFile.content) : undefined;
  const initialDraft = !postPath ? loadLocalWriterDraft(config, localDraftIdentifier(undefined)) : undefined;
  const [title, setTitle] = useState(initialDraft?.title ?? (initialParsed ? typeof initialParsed.frontmatter.title === "string" ? initialParsed.frontmatter.title : "" : initialPost?.title ?? ""));
  const [body, setBody] = useState(initialDraft?.body ?? initialParsed?.body ?? "");
  const [syndicationTargets, setSyndicationTargets] = useState<SyndicationProvider[]>(initialDraft?.syndicationTargets as SyndicationProvider[] | undefined ?? (initialParsed ? syndicationTargetsFromFrontmatter(initialParsed.frontmatter.syndicate, configuredSyndicationProviders) : configuredSyndicationProviders));
  const [categoryTargets, setCategoryTargets] = useState<string[]>(initialDraft?.categoryTargets ?? (initialParsed ? categoriesFromFrontmatter(initialParsed.frontmatter.categories, configuredCategories) : []));
  const [unmanagedCategoryTargets, setUnmanagedCategoryTargets] = useState<string[]>(initialParsed ? unmanagedCategoriesFromFrontmatter(initialParsed.frontmatter.categories, configuredCategories) : []);
  const [sha, setSha] = useState<string | undefined>(initialFile?.sha);
  const [path, setPath] = useState(postPath);
  const [slug, setSlug] = useState(initialFile?.slug ?? initialPost?.slug ?? "");
  const [originalMarkdown, setOriginalMarkdown] = useState<string | undefined>(initialFile?.content);
  const [postStatus, setPostStatus] = useState<PostStatus>(initialFile?.status ?? initialPost?.status ?? "draft");
  const [status, setStatus] = useState(initialDraft ? "Recovered local draft." : postPath && !initialFile ? "Loading..." : postPath ? "Saved" : "Unsaved");
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showDiscardDialog, setShowDiscardDialog] = useState(false);
  const [conflictPost, setConflictPost] = useState<PostFile>();
  const pendingAssets = useRef<PendingAsset[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const dirtyRef = useRef(Boolean(initialDraft));
  const lastRemoteCheck = useRef(Date.now());
  const currentSlug = useMemo(() => slug || slugForNewPost(title, body), [slug, title, body]);
  const hasContent = title.trim().length > 0 || body.trim().length > 0 || pendingAssets.current.length > 0;
  const hasUnsavedChanges = dirtyRef.current && Boolean(path || hasContent);
  const canEditSyndicationTargets = postStatus === "draft";
  const showSyndicationTargets = shouldShowSyndicationTargets(postStatus, configuredSyndicationProviders);
  const showCategoryTargets = shouldShowCategoryTargets(configuredCategories);

  function applyPost(post: PostFile, options: { force?: boolean; restoreDraft?: boolean } = {}): void {
    if (dirtyRef.current && !options.force) return;
    const parsed = parsePostMarkdown(post.content);
    const localDraft = options.restoreDraft ? loadLocalWriterDraft(config, localDraftIdentifier(post.path)) : undefined;
    setTitle(localDraft?.title ?? (typeof parsed.frontmatter.title === "string" ? parsed.frontmatter.title : ""));
    setBody(localDraft?.body ?? parsed.body);
    setSha(post.sha);
    setPath(post.path);
    setSlug(post.slug || filenameSlug(post.path));
    setOriginalMarkdown(post.content);
    setPostStatus(post.status);
    setSyndicationTargets(localDraft?.syndicationTargets as SyndicationProvider[] | undefined ?? syndicationTargetsFromFrontmatter(parsed.frontmatter.syndicate, configuredSyndicationProviders));
    setCategoryTargets(localDraft?.categoryTargets ?? categoriesFromFrontmatter(parsed.frontmatter.categories, configuredCategories));
    setUnmanagedCategoryTargets(unmanagedCategoriesFromFrontmatter(parsed.frontmatter.categories, configuredCategories));
    setStatus(localDraft ? "Recovered local draft." : "Saved");
    dirtyRef.current = Boolean(localDraft);
    onPostLoaded?.(post);
    if (localDraft) onToast?.("Recovered local draft.", "info");
  }

  function markUnsaved(): void {
    dirtyRef.current = true;
    setStatus("Unsaved");
  }

  useEffect(() => {
    if (!postPath) {
      if (!initialDraft) setStatus("Unsaved");
      return;
    }
    if (initialFile) applyPost(initialFile, { restoreDraft: true });
    adapter.readPost(postPath).then((post) => {
      if (dirtyRef.current && post.sha && sha && post.sha !== sha) {
        setConflictPost(post);
        return;
      }
      applyPost(post, { restoreDraft: true });
    }).catch((err: Error) => setError(err.message));
  }, [adapter, postPath]);

  useEffect(() => {
    if (!hasUnsavedChanges || !hasContent) return undefined;
    const identifier = localDraftIdentifier(path ?? postPath);
    const timer = window.setTimeout(() => {
      saveLocalWriterDraft(config, identifier, {
        title,
        body,
        syndicationTargets,
        categoryTargets
      });
    }, 600);
    return () => window.clearTimeout(timer);
  }, [body, categoryTargets, config, hasContent, hasUnsavedChanges, path, postPath, syndicationTargets, title]);

  useEffect(() => {
    if (!path) return undefined;
    const refreshIfStale = () => {
      if (document.visibilityState !== "visible" || busy || Date.now() - lastRemoteCheck.current < postFileCacheMaxAge) return;
      lastRemoteCheck.current = Date.now();
      adapter.readPost(path).then((post) => {
        if (dirtyRef.current && post.sha && sha && post.sha !== sha) {
          setConflictPost(post);
          return;
        }
        if (!dirtyRef.current) applyPost(post, { force: true, restoreDraft: true });
      }).catch(() => undefined);
    };
    document.addEventListener("visibilitychange", refreshIfStale);
    window.addEventListener("focus", refreshIfStale);
    return () => {
      document.removeEventListener("visibilitychange", refreshIfStale);
      window.removeEventListener("focus", refreshIfStale);
    };
  }, [adapter, busy, path, sha]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        if (!readOnly) void save(postStatus === "published" ? "published" : "draft");
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
    if (readOnly) return;
    setSyndicationTargets((current) => current.includes(provider)
      ? current.filter((item) => item !== provider)
      : [...current, provider]);
    markUnsaved();
  }

  function toggleCategoryTarget(category: string): void {
    if (readOnly) return;
    setCategoryTargets((current) => current.includes(category)
      ? current.filter((item) => item !== category)
      : [...current, category]);
    markUnsaved();
  }

  async function addFiles(files: FileList | File[]): Promise<void> {
    if (readOnly) return;
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
      dirtyRef.current = true;
    } catch (err) {
      setStatus("Unsaved");
      setError(err instanceof Error ? err.message : "Could not prepare images.");
    } finally {
      setBusy(false);
    }
  }

  async function save(nextStatus: "draft" | "published", options: { updateDate?: boolean } = {}): Promise<void> {
    if (busy || readOnly) return;
    setBusy(true);
    setStatus(pendingAssets.current.length > 0 ? "Uploading media..." : nextStatus === "published" ? "Publishing..." : "Saving...");
    setError(undefined);
    try {
      if (path && sha) {
        const remotePost = await adapter.readPost(path);
        if (remotePost.sha && remotePost.sha !== sha) {
          setConflictPost(remotePost);
          setStatus("Unsaved");
          setBusy(false);
          return;
        }
        onPostLoaded?.(remotePost);
      }
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
          const result = await adapter.savePost({ path: nextPath, slug: nextSlug, status: nextStatus, content, sha, media });
          const optimisticPost = { ...summarizePost(nextPath, content), content, sha: result.sha ?? sha };
          onPostSaved?.(optimisticPost);
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
      onPostSaved?.(savedPost);
      clearLocalWriterDraft(config, localDraftIdentifier(postPath));
      if (path) clearLocalWriterDraft(config, localDraftIdentifier(path));
      clearLocalWriterDraft(config, localDraftIdentifier(nextPath));
      dirtyRef.current = false;
      onToast?.(nextStatus === "published" ? "Post published." : "Post saved.", "success");
      setStatus(nextStatus === "published" ? "Published." : "Saved.");
    } catch (err) {
      setStatus("Unsaved");
      setError(err instanceof Error ? err.message : "Save failed.");
      onToast?.("Save failed.", "error");
    } finally {
      setBusy(false);
    }
  }

  async function remove(): Promise<void> {
    if (!path || busy || readOnly) return;
    setBusy(true);
    setStatus("Deleting...");
    setError(undefined);
    const deletedPath = path;
    const previousPost = originalMarkdown ? { ...summarizePost(path, originalMarkdown), content: originalMarkdown, sha } : initialFile;
    const mediaPaths = referencedMediaPaths(originalMarkdown ?? body, config.mediaPath);
    onPostDeleted?.(deletedPath);
    navigate("/posts");
    try {
      await adapter.deletePost({ path: deletedPath, slug: currentSlug, sha, mediaPaths });
      clearLocalWriterDraft(config, localDraftIdentifier(deletedPath));
      onToast?.("Post deleted.", "success");
    } catch (err) {
      if (previousPost) onPostSaved?.(previousPost);
      onToast?.(err instanceof Error ? err.message : "Delete failed.", "error");
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

  function reloadConflict(): void {
    if (!conflictPost) return;
    clearLocalWriterDraft(config, localDraftIdentifier(conflictPost.path));
    pendingAssets.current = [];
    setConflictPost(undefined);
    dirtyRef.current = false;
    applyPost(conflictPost, { force: true });
  }

  function keepEditingConflict(): void {
    setConflictPost(undefined);
    markUnsaved();
  }

  function discardChanges(): void {
    clearLocalWriterDraft(config, localDraftIdentifier(path ?? postPath));
    clearLocalWriterDraft(config, localDraftIdentifier(undefined));
    navigate("/posts");
  }

  return (
    <main className="editor">
      <header className="editor-bar">
        <Button icon={<ArrowLeftIcon />} aria-label="Back" onClick={back} disabled={busy}>Back</Button>
        <div className="editor-actions">
          {path ? <Button icon={<TrashIcon />} aria-label="Delete" className="danger" onClick={() => setShowDeleteDialog(true)} disabled={busy || readOnly}>Delete</Button> : null}
          <Button icon={<ImageIcon />} aria-label="Insert image" onClick={() => fileInputRef.current?.click()} disabled={busy || readOnly}>Insert image</Button>
          {postStatus === "published" ? (
            <Button icon={<SaveIcon />} aria-label={busy ? "Saving" : "Save"} onClick={() => save("published")} disabled={busy || readOnly}>Save</Button>
          ) : (
            <>
              <Button icon={<SaveIcon />} aria-label={busy ? "Saving draft" : "Save draft"} onClick={() => save("draft")} disabled={busy || readOnly}>Save draft</Button>
              <Button icon={<UploadIcon />} aria-label={busy ? "Publishing" : "Publish"} onClick={() => save("published", { updateDate: true })} disabled={busy || readOnly}>Publish</Button>
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
              <Button icon={<TrashIcon />} className="danger" onClick={remove} disabled={busy || readOnly}>{busy ? "Deleting" : "Delete"}</Button>
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
              <Button className="danger" onClick={discardChanges}>Discard</Button>
            </div>
          </Dialog>
        </div>
      ) : null}
      {conflictPost ? (
        <div className="modal-backdrop" role="presentation">
          <Dialog>
            <h2>Post changed elsewhere</h2>
            <p className="muted">This post has changed in the repository since you opened it. Reload the latest version or keep editing your local changes.</p>
            <div className="dialog-actions">
              <Button onClick={keepEditingConflict}>Keep editing</Button>
              <Button icon={<RefreshIcon />} onClick={reloadConflict}>Reload</Button>
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
      {readOnly ? <p className="notice editor-notice">You are offline. Editing actions are paused until the connection returns.</p> : null}
      <input className="title-input" value={title} onChange={(event) => {
        if (readOnly) return;
        setTitle(event.target.value);
        markUnsaved();
      }} placeholder="Title (optional)" readOnly={readOnly} />
      {showSyndicationTargets ? (
        <section className="frontmatter-targets" aria-label="Syndication targets">
          <p>Syndicate to</p>
          <div>
            {configuredSyndicationProviders.map((provider) => (
              <label key={provider} className="target-chip">
                <input
                  type="checkbox"
                  checked={syndicationTargets.includes(provider)}
                  disabled={readOnly}
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
                  disabled={readOnly}
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
          if (readOnly) return;
          setBody(event.target.value);
          markUnsaved();
        }}
        onPaste={(event) => {
          if (!busy) void addFiles(event.clipboardData.files);
        }}
        onDrop={(event) => {
          event.preventDefault();
          if (!busy) void addFiles(event.dataTransfer.files);
        }}
        onDragOver={(event) => event.preventDefault()}
        readOnly={readOnly}
        placeholder="Write..."
      />
      <StatusBar status={status} error={error} busy={busy} />
    </main>
  );
}
