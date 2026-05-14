import { copyFile, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import MarkdownIt from "markdown-it";

const root = process.cwd();
const docsDir = path.join(root, "docs");
const outDir = path.join(root, "docs-site");
const md = new MarkdownIt({ html: true, linkify: true, typographer: true });
const terminalLanguages = new Set(["bash", "sh", "shell", "zsh"]);
const languageLabels = {
  bash: "Terminal",
  sh: "Terminal",
  shell: "Terminal",
  zsh: "Terminal",
  ts: "TypeScript",
  js: "JavaScript",
  md: "Markdown",
  markdown: "Markdown",
  yaml: "YAML",
  yml: "YAML",
  liquid: "Liquid",
  env: ".env",
  txt: "Text",
  text: "Text"
};

md.renderer.rules.fence = (tokens, index) => {
  const token = tokens[index];
  const language = token.info.trim().split(/\s+/)[0]?.toLowerCase() || "text";
  return terminalLanguages.has(language) ? renderTerminalBlock(token.content, language) : renderCodeBlock(token.content, language);
};

const navGroups = [
  {
    title: "Start",
    pages: [
      { slug: "getting-started", file: "getting-started.md" },
      { slug: "writing-posts", file: "writing-posts.md" },
      { slug: "themes", file: "themes.md" }
    ]
  },
  {
    title: "Deployment",
    pages: [
      { slug: "deployment", file: "deployment/index.md" },
      { slug: "deployment/cloudflare-workers", file: "deployment/cloudflare-workers.md" },
      { slug: "deployment/github-pages", file: "deployment/github-pages.md" },
      { slug: "deployment/gitlab-pages", file: "deployment/gitlab-pages.md" }
    ]
  },
  {
    title: "Syndication",
    pages: [
      { slug: "syndication", file: "syndication/index.md" },
      { slug: "syndication/mastodon", file: "syndication/mastodon.md" },
      { slug: "syndication/bluesky", file: "syndication/bluesky.md" },
      { slug: "syndication/flickr", file: "syndication/flickr.md" }
    ]
  },
  {
    title: "CI",
    pages: [
      { slug: "ci", file: "ci/index.md" },
      { slug: "github-actions", file: "github-actions.md" },
      { slug: "gitlab-ci", file: "gitlab-ci.md" }
    ]
  },
  {
    title: "Extras",
    pages: [
      { slug: "writer", file: "writer.md" },
      { slug: "troubleshooting", file: "troubleshooting.md" },
      { slug: "upgrading", file: "upgrading.md" }
    ]
  }
];

function titleFromMarkdown(markdown, fallback) {
  return markdown.match(/^#\s+(.+)$/m)?.[1]?.trim() ?? fallback;
}

function labelFromSlug(slug) {
  return slug.split("-").map((part) => `${part.charAt(0).toUpperCase()}${part.slice(1)}`).join(" ");
}

function renderTerminalBlock(code, language) {
  const lines = code.replace(/\n$/, "").split("\n");
  const body = lines.map((line) => `<span class="terminal-line"><span class="terminal-prompt">$</span><span>${escapeHtml(line)}</span></span>`).join("");
  return `<figure class="code-block terminal-block" data-language="${escapeHtml(language)}">
    <figcaption><span class="window-dots" aria-hidden="true"><span></span><span></span><span></span></span><span>${languageLabels[language] ?? "Terminal"}</span></figcaption>
    <pre><code>${body}</code></pre>
  </figure>`;
}

function renderCodeBlock(code, language) {
  const label = languageLabels[language] ?? language.toUpperCase();
  return `<figure class="code-block source-block" data-language="${escapeHtml(language)}">
    <figcaption><span>${escapeHtml(label)}</span></figcaption>
    <pre><code class="language-${escapeHtml(language)}">${highlightCode(code.replace(/\n$/, ""), language)}</code></pre>
  </figure>`;
}

function highlightCode(code, language) {
  if (["ts", "js"].includes(language)) return code.split("\n").map(highlightTypeScriptLine).join("\n");
  if (["yaml", "yml", "env"].includes(language)) return code.split("\n").map(highlightKeyValueLine).join("\n");
  if (["md", "markdown"].includes(language)) return code.split("\n").map(highlightMarkdownLine).join("\n");
  if (language === "liquid") return escapeHtml(code)
    .replace(/({[{%][\s\S]*?[}%]})/g, '<span class="syntax-template">$1</span>')
    .replace(/(&lt;\/?[\w-]+(?:\s[^&]*)?&gt;)/g, '<span class="syntax-tag">$1</span>');
  return escapeHtml(code);
}

function highlightTypeScriptLine(line) {
  let output = "";
  let index = 0;
  while (index < line.length) {
    if (line.startsWith("//", index)) {
      output += `<span class="syntax-comment">${escapeHtml(line.slice(index))}</span>`;
      break;
    }
    const char = line[index];
    if (char === '"' || char === "'" || char === "`") {
      const end = readQuotedString(line, index, char);
      output += `<span class="syntax-string">${escapeHtml(line.slice(index, end))}</span>`;
      index = end;
      continue;
    }
    let next = index + 1;
    while (next < line.length && !line.startsWith("//", next) && !['"', "'", "`"].includes(line[next])) next += 1;
    output += highlightTypeScriptText(line.slice(index, next));
    index = next;
  }
  return output;
}

function readQuotedString(line, start, quote) {
  let index = start + 1;
  while (index < line.length) {
    if (line[index] === "\\") {
      index += 2;
      continue;
    }
    if (line[index] === quote) return index + 1;
    index += 1;
  }
  return line.length;
}

function highlightTypeScriptText(text) {
  return escapeHtml(text)
    .replace(/\b(import|from|export|default|const|let|return|true|false|new|await|async|type|string|number|boolean)\b/g, '<span class="syntax-keyword">$1</span>')
    .replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="syntax-number">$1</span>')
    .replace(/\b([A-Za-z_$][\w$]*)(?=\s*:)/g, '<span class="syntax-property">$1</span>');
}

function highlightKeyValueLine(line) {
  const escaped = escapeHtml(line);
  if (/^\s*#/.test(line)) return `<span class="syntax-comment">${escaped}</span>`;
  return escaped
    .replace(/^(\s*[-]?\s*)([A-Za-z0-9_.-]+)(\s*:)/, '$1<span class="syntax-property">$2</span>$3')
    .replace(/^(\s*)([A-Z0-9_]+)(=)/, '$1<span class="syntax-property">$2</span>$3')
    .replace(/(&quot;.*?&quot;|'.*?')/g, '<span class="syntax-string">$1</span>');
}

function highlightMarkdownLine(line) {
  const escaped = escapeHtml(line);
  if (/^\s*---\s*$/.test(line)) return `<span class="syntax-comment">${escaped}</span>`;
  if (/^\s*#/.test(line)) return `<span class="syntax-keyword">${escaped}</span>`;
  if (/^\s*[A-Za-z0-9_.-]+:/.test(line)) return escaped.replace(/^(\s*)([A-Za-z0-9_.-]+)(:)/, '$1<span class="syntax-property">$2</span>$3');
  return escaped.replace(/(\*\*[^*]+\*\*|_[^_]+_|`[^`]+`)/g, '<span class="syntax-string">$1</span>');
}

function pageLayout({ title, content, pages, groups, currentSlug }) {
  const nav = groups.map((group) => `<div class="nav-group"><p>${escapeHtml(group.title)}</p>${group.pages.map((page) => `<a ${page.slug === currentSlug ? 'aria-current="page"' : ""} href="/${page.slug}/">${escapeHtml(page.title)}</a>`).join("")}</div>`).join("");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)} - Inkstead</title>
  <link rel="icon" href="/favicon.png" type="image/png">
  <link rel="apple-touch-icon" href="/assets/inkstead.png">
  <style>
    :root {
      color-scheme: light dark;
      --paper: #fff9ec;
      --paper-strong: #fff1d3;
      --ink: #062748;
      --muted: #5d6470;
      --line: rgba(6, 39, 72, 0.14);
      --copy: #26384b;
      --link: #0a5f97;
      --sidebar-bg: rgba(255, 249, 236, 0.84);
      --nav-hover: rgba(6, 39, 72, 0.06);
      --nav-current: linear-gradient(135deg, var(--ink), #0b416f);
      --nav-current-text: #fff;
      --mobile-control-bg: rgba(255, 255, 255, 0.52);
      --inline-code-bg: rgba(255, 255, 255, 0.58);
      --inline-code-border: rgba(6, 39, 72, 0.12);
      --pre-bg: #08213a;
      --pre-text: #fff8e8;
      --pre-shadow: rgba(6, 39, 72, 0.12);
      --pre-header: rgba(255, 255, 255, 0.08);
      --pre-border: rgba(255, 255, 255, 0.12);
      --terminal-prompt: #5fc9b5;
      --syntax-comment: #9fb0bf;
      --syntax-keyword: #ffb86b;
      --syntax-string: #b9f0d8;
      --syntax-number: #f7b733;
      --syntax-property: #9fd5ff;
      --syntax-tag: #ff9f8b;
      --syntax-template: #d6c9ff;
      --body-bg:
        radial-gradient(circle at 80% 8%, rgba(255, 90, 47, 0.16), transparent 30%),
        radial-gradient(circle at 12% 74%, rgba(95, 201, 181, 0.18), transparent 32%),
        linear-gradient(135deg, #fffdf7 0%, var(--paper) 52%, #fff5df 100%);
      --brand-shadow: rgba(6, 39, 72, 0.16);
      --orange: #ff5a2f;
      --gold: #f7b733;
      --mint: #5fc9b5;
      --violet: #6255c7;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --paper: #151412;
        --paper-strong: #211d18;
        --ink: #f4efe7;
        --muted: #aaa198;
        --line: rgba(244, 239, 231, 0.14);
        --copy: #d9d1c7;
        --link: #9fd5ff;
        --sidebar-bg: rgba(21, 20, 18, 0.84);
        --nav-hover: rgba(244, 239, 231, 0.08);
        --nav-current: linear-gradient(135deg, #f4efe7, #b9c7ff);
        --nav-current-text: #12110f;
        --mobile-control-bg: rgba(255, 255, 255, 0.06);
        --inline-code-bg: rgba(255, 255, 255, 0.08);
        --inline-code-border: rgba(244, 239, 231, 0.14);
        --pre-bg: #090d13;
        --pre-text: #f8efe1;
        --pre-shadow: rgba(0, 0, 0, 0.32);
        --pre-header: rgba(255, 255, 255, 0.07);
        --pre-border: rgba(255, 255, 255, 0.11);
        --terminal-prompt: #5fc9b5;
        --syntax-comment: #758594;
        --syntax-keyword: #f7b733;
        --syntax-string: #9fe3c9;
        --syntax-number: #ffd27a;
        --syntax-property: #9fd5ff;
        --syntax-tag: #ff9f8b;
        --syntax-template: #c9bcff;
        --body-bg:
          radial-gradient(circle at 80% 8%, rgba(255, 90, 47, 0.12), transparent 30%),
          radial-gradient(circle at 12% 74%, rgba(95, 201, 181, 0.12), transparent 32%),
          linear-gradient(135deg, #12110f 0%, var(--paper) 52%, #1b1713 100%);
        --brand-shadow: rgba(0, 0, 0, 0.36);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font: 17px/1.68 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink);
      background: var(--body-bg);
    }
    .shell {
      display: grid;
      grid-template-columns: 300px minmax(0, 1fr);
      min-height: 100vh;
    }
    .sidebar {
      position: sticky;
      top: 0;
      align-self: start;
      height: 100vh;
      border-right: 1px solid var(--line);
      padding: 30px 24px;
      background: var(--sidebar-bg);
      backdrop-filter: blur(18px);
      display: flex;
      flex-direction: column;
    }
    .brand {
      display: grid;
      grid-template-columns: 56px 1fr;
      gap: 14px;
      align-items: center;
      margin-bottom: 30px;
      text-decoration: none;
      color: var(--ink);
    }
    .brand img {
      width: 56px;
      height: 56px;
      border-radius: 18px;
      box-shadow: 0 14px 30px var(--brand-shadow);
    }
    .brand strong {
      display: block;
      font-size: 1.24rem;
      letter-spacing: 0;
    }
    .brand span {
      display: block;
      color: var(--muted);
      font-size: 0.86rem;
      line-height: 1.3;
    }
    .mobile-nav-toggle { display: none; }
    nav a {
      display: block;
      margin: 3px 0;
      padding: 8px 10px;
      border-radius: 8px;
      color: var(--ink);
      text-decoration: none;
    }
    .nav-group { margin-top: 22px; }
    .nav-group p {
      margin: 0 0 8px;
      padding: 0 10px;
      color: var(--muted);
      font-size: 0.72rem;
      font-weight: 800;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    nav a:hover { background: var(--nav-hover); }
    nav a[aria-current="page"] {
      color: var(--nav-current-text);
      background: var(--nav-current);
      font-weight: 700;
    }
    #docs-nav {
      min-height: 0;
      overflow-y: auto;
      overscroll-behavior: contain;
    }
    .sidebar-footer {
      margin-top: auto;
      padding: 28px 10px 0;
      color: var(--muted);
      font-size: 0.82rem;
      line-height: 1.4;
    }
    .sidebar-footer a {
      color: var(--ink);
      font-weight: 700;
    }
    .mobile-page-footer { display: none; }
    main {
      width: min(820px, calc(100vw - 360px));
      margin: 0 auto;
      padding: 64px 32px 80px;
    }
    main::before {
      content: "";
      display: block;
      width: 92px;
      height: 6px;
      margin-bottom: 28px;
      border-radius: 999px;
      background: linear-gradient(90deg, var(--orange), var(--gold), var(--mint), var(--violet));
    }
    h1, h2, h3 {
      line-height: 1.14;
      letter-spacing: 0;
      color: var(--ink);
    }
    h1 {
      margin-top: 0;
      font-size: clamp(2.2rem, 4vw, 4.6rem);
      max-width: 10ch;
    }
    h2 { margin-top: 2.4em; font-size: 1.55rem; }
    h3 { margin-top: 1.8em; font-size: 1.16rem; }
    p, li { color: var(--copy); }
    a { color: var(--link); text-decoration-thickness: 0.08em; text-underline-offset: 0.18em; }
    code { font: 0.95em ui-monospace, SFMono-Regular, Menlo, monospace; }
    :not(pre) > code {
      padding: 0.12em 0.34em;
      border: 1px solid var(--inline-code-border);
      border-radius: 5px;
      background: var(--inline-code-bg);
    }
    pre {
      overflow-x: auto;
      padding: 18px;
      border: 1px solid var(--inline-code-border);
      border-radius: 10px;
      background: var(--pre-bg);
      color: var(--pre-text);
      box-shadow: 0 20px 50px var(--pre-shadow);
    }
    pre code { color: inherit; }
    .code-block {
      overflow: hidden;
      margin: 28px 0;
      border: 1px solid var(--pre-border);
      border-radius: 12px;
      background: var(--pre-bg);
      color: var(--pre-text);
      box-shadow: 0 20px 50px var(--pre-shadow);
    }
    .code-block figcaption {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 38px;
      padding: 0 14px;
      border-bottom: 1px solid var(--pre-border);
      background: var(--pre-header);
      color: rgba(255, 248, 232, 0.76);
      font: 0.78rem ui-monospace, SFMono-Regular, Menlo, monospace;
      letter-spacing: 0.02em;
    }
    .code-block pre {
      margin: 0;
      border: 0;
      border-radius: 0;
      box-shadow: none;
    }
    .window-dots {
      display: inline-flex;
      gap: 6px;
      align-items: center;
    }
    .window-dots span {
      width: 10px;
      height: 10px;
      border-radius: 50%;
    }
    .window-dots span:nth-child(1) { background: var(--orange); }
    .window-dots span:nth-child(2) { background: var(--gold); }
    .window-dots span:nth-child(3) { background: var(--mint); }
    .terminal-block figcaption > span:last-child {
      margin-left: auto;
    }
    .terminal-line {
      display: grid;
      grid-template-columns: 1.4em minmax(0, 1fr);
      gap: 0.6em;
      min-width: max-content;
    }
    .terminal-prompt {
      color: var(--terminal-prompt);
      user-select: none;
    }
    .syntax-comment { color: var(--syntax-comment); }
    .syntax-keyword { color: var(--syntax-keyword); }
    .syntax-string { color: var(--syntax-string); }
    .syntax-number { color: var(--syntax-number); }
    .syntax-property { color: var(--syntax-property); }
    .syntax-tag { color: var(--syntax-tag); }
    .syntax-template { color: var(--syntax-template); }
    blockquote {
      margin-left: 0;
      padding-left: 18px;
      border-left: 5px solid var(--gold);
      color: var(--muted);
    }
    main img {
      display: block;
      max-width: 100%;
      height: auto;
      margin: 34px 0;
    }
    @media (max-width: 860px) {
      .shell { display: block; }
      .sidebar {
        position: sticky;
        z-index: 10;
        height: auto;
        border-right: 0;
        border-bottom: 1px solid var(--line);
        padding: 14px 18px;
      }
      .brand {
        grid-template-columns: 38px 1fr;
        gap: 10px;
        margin-bottom: 0;
      }
      .brand img {
        width: 38px;
        height: 38px;
        border-radius: 12px;
        box-shadow: 0 10px 24px var(--brand-shadow);
      }
      .brand strong { font-size: 1.04rem; }
      .brand span span { display: none; }
      .mobile-nav-toggle {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        width: 100%;
        margin: 14px 0 0;
        padding: 9px 11px;
        border: 1px solid var(--line);
        border-radius: 8px;
        color: var(--ink);
        background: var(--mobile-control-bg);
        font: inherit;
        font-size: 0.92rem;
        font-weight: 800;
        cursor: pointer;
      }
      .mobile-nav-toggle::after {
        content: "";
        width: 9px;
        height: 9px;
        border-right: 2px solid currentColor;
        border-bottom: 2px solid currentColor;
        transform: rotate(45deg) translateY(-2px);
      }
      .mobile-nav-toggle[aria-expanded="true"]::after {
        transform: rotate(225deg) translateY(-2px);
      }
      nav[hidden] { display: none; }
      #docs-nav {
        padding-top: 12px;
        max-height: calc(100vh - 116px);
        overflow-y: auto;
        overscroll-behavior: contain;
      }
      .nav-group { margin-top: 14px; }
      .sidebar-footer { display: none; }
      main { width: auto; padding: 38px 22px 42px; }
      .mobile-page-footer {
        display: block;
        padding: 0 22px 32px;
        color: var(--muted);
        font-size: 0.86rem;
      }
      .mobile-page-footer a {
        color: var(--ink);
        font-weight: 700;
      }
      h1 { max-width: none; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <aside class="sidebar">
      <a class="brand" href="/">
        <img src="/assets/inkstead.png" alt="">
        <span><strong>Inkstead</strong><span>Indie-web publishing engine</span></span>
      </a>
      <button class="mobile-nav-toggle" type="button" aria-controls="docs-nav" aria-expanded="false">Menu</button>
      <nav id="docs-nav">${nav}</nav>
      <p class="sidebar-footer">&copy; ${new Date().getFullYear()} <a href="https://ivonunes.uk" target="_blank" rel="noopener noreferrer">Ivo Nunes</a></p>
    </aside>
    <main>${content}</main>
    <p class="mobile-page-footer">&copy; ${new Date().getFullYear()} <a href="https://ivonunes.uk" target="_blank" rel="noopener noreferrer">Ivo Nunes</a></p>
  </div>
  <script>
    const toggle = document.querySelector(".mobile-nav-toggle");
    const nav = document.querySelector("#docs-nav");
    const syncNav = () => {
      if (!toggle || !nav) return;
      const compact = window.matchMedia("(max-width: 860px)").matches;
      nav.hidden = compact && toggle.getAttribute("aria-expanded") !== "true";
    };
    toggle?.addEventListener("click", () => {
      toggle.setAttribute("aria-expanded", toggle.getAttribute("aria-expanded") === "true" ? "false" : "true");
      syncNav();
    });
    window.addEventListener("resize", syncNav);
    syncNav();
  </script>
</body>
</html>
`;
}

function landingLayout() {
  const currentYear = new Date().getFullYear();

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Inkstead</title>
  <link rel="icon" href="/favicon.png" type="image/png">
  <link rel="apple-touch-icon" href="/assets/inkstead.png">
  <style>
    :root {
      color-scheme: light dark;
      --paper: #fff9ec;
      --ink: #062748;
      --muted: #5d6470;
      --line: rgba(6, 39, 72, 0.14);
      --copy: #26384b;
      --link: #0a5f97;
      --hero-bg:
        linear-gradient(120deg, rgba(255, 90, 47, 0.12), transparent 28%),
        linear-gradient(300deg, rgba(95, 201, 181, 0.16), transparent 34%),
        linear-gradient(135deg, #fffdf7 0%, var(--paper) 56%, #fff1d3 100%);
      --primary-bg: linear-gradient(135deg, var(--ink), #0b416f);
      --primary-text: #fff;
      --primary-shadow: rgba(6, 39, 72, 0.18);
      --secondary-bg: rgba(255, 255, 255, 0.46);
      --mark-shadow: rgba(6, 39, 72, 0.18);
      --brand-shadow: rgba(6, 39, 72, 0.12);
      --orange: #ff5a2f;
      --gold: #f7b733;
      --mint: #5fc9b5;
      --violet: #6255c7;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --paper: #151412;
        --ink: #f4efe7;
        --muted: #aaa198;
        --line: rgba(244, 239, 231, 0.14);
        --copy: #d9d1c7;
        --link: #9fd5ff;
        --hero-bg:
          linear-gradient(120deg, rgba(255, 90, 47, 0.11), transparent 28%),
          linear-gradient(300deg, rgba(95, 201, 181, 0.12), transparent 34%),
          linear-gradient(135deg, #12110f 0%, var(--paper) 56%, #201a14 100%);
        --primary-bg: linear-gradient(135deg, #f4efe7, #b9c7ff);
        --primary-text: #12110f;
        --primary-shadow: rgba(0, 0, 0, 0.34);
        --secondary-bg: rgba(255, 255, 255, 0.06);
        --mark-shadow: rgba(0, 0, 0, 0.38);
        --brand-shadow: rgba(0, 0, 0, 0.32);
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font: 17px/1.65 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--ink);
      background: var(--hero-bg);
    }
    .page { width: min(1120px, calc(100vw - 40px)); margin: 0 auto; }
    header {
      display: flex;
      align-items: center;
      padding: 28px 0;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
      color: var(--ink);
      text-decoration: none;
      font-weight: 800;
      font-size: 1.18rem;
    }
    .brand-mark { display: none; }
    a { color: var(--link); text-decoration-thickness: 0.08em; text-underline-offset: 0.18em; }
    .hero {
      display: grid;
      grid-template-columns: minmax(0, 1.05fr) minmax(260px, 0.75fr);
      gap: 48px;
      align-items: center;
      padding: 56px 0 72px;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      margin: 0 0 18px;
      color: var(--muted);
      font-weight: 800;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      font-size: 0.78rem;
    }
    .eyebrow::before {
      content: "";
      width: 54px;
      height: 5px;
      border-radius: 999px;
      background: linear-gradient(90deg, var(--orange), var(--gold), var(--mint), var(--violet));
    }
    h1 {
      max-width: 9.5ch;
      margin: 0;
      font-size: clamp(3.6rem, 9vw, 8rem);
      line-height: 0.95;
      letter-spacing: 0;
    }
    .hero p {
      max-width: 56ch;
      margin: 24px 0 0;
      color: var(--copy);
      font-size: 1.18rem;
    }
    .actions {
      display: flex;
      gap: 14px;
      flex-wrap: wrap;
      margin-top: 34px;
    }
    .button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 46px;
      padding: 0 18px;
      border-radius: 8px;
      font-weight: 800;
      text-decoration: none;
    }
    .button.primary {
      color: var(--primary-text);
      background: var(--primary-bg);
      box-shadow: 0 18px 40px var(--primary-shadow);
    }
    .button.secondary {
      color: var(--ink);
      border: 1px solid var(--line);
      background: var(--secondary-bg);
    }
    .mark {
      justify-self: center;
      width: min(340px, 70vw);
      border-radius: 56px;
      box-shadow: 0 34px 80px var(--mark-shadow);
    }
    footer {
      padding: 0 0 34px;
      color: var(--muted);
      font-size: 0.92rem;
    }
    footer a {
      color: var(--ink);
      font-weight: 700;
    }
    @media (max-width: 860px) {
      .page { width: min(100vw - 36px, 620px); }
      header { align-items: flex-start; flex-direction: column; padding: 24px 0 12px; }
      .brand { font-size: 1.08rem; }
      .brand-mark {
        display: block;
        width: 38px;
        height: 38px;
        border-radius: 12px;
        box-shadow: 0 10px 26px var(--brand-shadow);
      }
      .hero {
        grid-template-columns: 1fr;
        gap: 0;
        padding: 26px 0 48px;
      }
      .mark { display: none; }
      .eyebrow {
        align-items: flex-start;
        gap: 10px;
        margin-bottom: 14px;
        font-size: 0.68rem;
        line-height: 1.35;
      }
      .eyebrow::before {
        flex: 0 0 42px;
        width: 42px;
        margin-top: 0.45em;
      }
      h1 {
        max-width: none;
        font-size: clamp(2.7rem, 10.8vw, 4rem);
        line-height: 1;
      }
      .hero p {
        margin-top: 22px;
        font-size: 1.02rem;
        line-height: 1.58;
      }
      .actions {
        gap: 10px;
        margin-top: 28px;
      }
      .button {
        min-height: 44px;
        padding: 0 15px;
      }
      footer { padding-bottom: 28px; }
    }
    @media (max-width: 460px) {
      .brand-mark {
        width: 34px;
        height: 34px;
        border-radius: 10px;
      }
      h1 { font-size: clamp(2.35rem, 11.5vw, 3rem); }
      .actions { display: grid; grid-template-columns: 1fr; }
      .button { width: 100%; }
    }
  </style>
</head>
<body>
  <div class="page">
    <header>
      <a class="brand" href="/"><img class="brand-mark" src="/assets/inkstead.png" alt="">Inkstead</a>
    </header>
    <main>
      <section class="hero">
        <div>
          <p class="eyebrow">Personal publishing, owned end to end</p>
          <h1>Build a website that feels like home.</h1>
          <p>Inkstead is an opinionated publishing engine for personal indie websites. Write in Markdown, build a static site, deploy anywhere, and optionally syndicate posts to social media.</p>
          <div class="actions">
            <a class="button primary" href="/getting-started/">Get started</a>
            <a class="button secondary" href="https://github.com/ivonunes/inkstead" target="_blank" rel="noopener noreferrer">View on GitHub</a>
          </div>
        </div>
        <img class="mark" src="/assets/inkstead.png" alt="">
      </section>
    </main>
    <footer>&copy; ${currentYear} <a href="https://ivonunes.uk" target="_blank" rel="noopener noreferrer">Ivo Nunes</a></footer>
  </div>
</body>
</html>
`;
}

function escapeHtml(value) {
  return String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

async function main() {
  const docs = [];
  for (const item of navGroups.flatMap((group) => group.pages)) {
    const file = path.join(docsDir, item.file);
    const markdown = await readFile(file, "utf8");
    docs.push({ slug: item.slug, file: item.file, title: titleFromMarkdown(markdown, labelFromSlug(item.slug.split("/").pop() ?? item.slug)), markdown });
  }
  const pages = [{ slug: "index", title: "Overview" }, ...docs.map(({ slug, title }) => ({ slug, title }))];
  const groups = navGroups.map((group) => ({
    title: group.title,
    pages: group.pages.map((page) => pages.find((item) => item.slug === page.slug)).filter(Boolean)
  }));
  await rm(outDir, { recursive: true, force: true });
  await mkdir(outDir, { recursive: true });
  await mkdir(path.join(outDir, "assets"), { recursive: true });
  for (const item of await readdir(path.join(docsDir, "assets"), { withFileTypes: true })) {
    if (!item.isFile()) continue;
    await copyFile(path.join(docsDir, "assets", item.name), path.join(outDir, "assets", item.name));
  }
  await copyFile(path.join(docsDir, "assets/inkstead.png"), path.join(outDir, "favicon.png"));

  await writeFile(path.join(outDir, "index.html"), landingLayout());

  for (const doc of docs) {
    const pageDir = path.join(outDir, doc.slug);
    await mkdir(pageDir, { recursive: true });
    await writeFile(path.join(pageDir, "index.html"), pageLayout({
      title: doc.title,
      content: md.render(doc.markdown),
      pages,
      groups,
      currentSlug: doc.slug
    }));
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
