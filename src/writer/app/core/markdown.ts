export function extractMarkdownImageReferences(markdown: string): string[] {
  const refs = [
    ...markdown.matchAll(/!\[[^\]]*]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g),
    ...markdown.matchAll(/<img[^>]+src=["']([^"']+)["']/gi)
  ].map((match) => match[1]).filter(Boolean);
  return [...new Set(refs)];
}

export function renderPreviewMarkdown(markdown: string): string {
  const escaped = markdown
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  return escaped
    .replace(/^### (.*)$/gm, "<h3>$1</h3>")
    .replace(/^## (.*)$/gm, "<h2>$1</h2>")
    .replace(/^# (.*)$/gm, "<h1>$1</h1>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/_([^_]+)_/g, "<em>$1</em>")
    .replace(/!\[([^\]]*)]\(([^)\s]+)\)/g, '<img alt="$1" src="$2">')
    .replace(/\[([^\]]+)]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2" rel="noopener noreferrer" target="_blank">$1</a>')
    .split(/\n{2,}/)
    .map((block) => block.match(/^<h[1-3]|^<img/) ? block : `<p>${block.replace(/\n/g, "<br>")}</p>`)
    .join("\n");
}
