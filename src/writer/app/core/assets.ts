import { extractMarkdownImageReferences } from "./markdown.js";

export const maxMediaUploadBytes = 25 * 1024 * 1024;

export interface AssetFile {
  path: string;
  name: string;
  sha?: string;
}

export interface PendingAsset {
  file: File;
  path: string;
  markdownReference: string;
}

export function mediaAssetPath(mediaPath: string, filename: string): string {
  return `${mediaPath.replace(/\/+$/g, "")}/${filename}`;
}

export function markdownMediaReference(mediaPath: string, filename: string): string {
  const publicMediaFolder = mediaPath.replace(/\/+$/g, "").split("/").filter(Boolean).pop();
  if (publicMediaFolder) return `/${publicMediaFolder}/${filename}`;
  return `/${mediaAssetPath(mediaPath, filename)}`;
}

export function safeAssetFilename(name: string): string {
  const extension = name.includes(".") ? `.${name.split(".").pop()}` : "";
  const base = name.replace(/\.[^.]+$/, "") || "image";
  const safeBase = base
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60) || "image";
  return `${safeBase}${extension.toLowerCase()}`;
}

export function uniqueAssetFilename(name: string, existingNames: Iterable<string>): string {
  const safeName = safeAssetFilename(name);
  const extension = safeName.includes(".") ? `.${safeName.split(".").pop()}` : "";
  const base = extension ? safeName.slice(0, -extension.length) : safeName;
  const existing = new Set([...existingNames].map((item) => item.toLowerCase()));
  if (!existing.has(safeName.toLowerCase())) return safeName;
  for (let index = 2; ; index += 1) {
    const candidate = `${base}-${index}${extension}`;
    if (!existing.has(candidate.toLowerCase())) return candidate;
  }
}

export function referencedMediaPaths(markdown: string, mediaPath: string): string[] {
  const cleanMediaPath = mediaPath.replace(/\/+$/g, "");
  const publicMediaFolder = cleanMediaPath.split("/").filter(Boolean).pop();
  const refs = extractMarkdownImageReferences(markdown);
  return [...new Set(refs.map((ref) => {
    const clean = decodeURI(ref.split(/[?#]/)[0] ?? ref).replace(/^\/+/, "");
    if (publicMediaFolder && clean.startsWith(`${publicMediaFolder}/`)) {
      return `${cleanMediaPath}/${clean.slice(publicMediaFolder.length + 1)}`;
    }
    return clean.startsWith(`${cleanMediaPath}/`) ? clean : undefined;
  }).filter((ref): ref is string => Boolean(ref)))];
}

export async function fileToBase64(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  let binary = "";
  for (const byte of new Uint8Array(buffer)) binary += String.fromCharCode(byte);
  return btoa(binary);
}
