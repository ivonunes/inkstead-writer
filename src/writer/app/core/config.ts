export type WriterProvider = "github" | "gitlab" | "local";

export interface WriterPublicConfig {
  provider: WriterProvider;
  owner?: string;
  repo?: string;
  branch?: string;
  postsPath: string;
  mediaPath: string;
}

export async function loadWriterConfig(): Promise<WriterPublicConfig> {
  const response = await fetch("./inkstead-writer.config.json", { cache: "no-store" });
  if (!response.ok) {
    throw new Error("Could not load Inkstead Writer config.");
  }
  return response.json() as Promise<WriterPublicConfig>;
}
