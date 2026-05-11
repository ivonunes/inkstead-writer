import { cp, mkdir } from "node:fs/promises";

await mkdir("dist/core/templates/defaults", { recursive: true });
await cp("src/core/templates/defaults", "dist/core/templates/defaults", { recursive: true });
await mkdir("dist/writer", { recursive: true });
await cp("src/writer/dist", "dist/writer/dist", { recursive: true });
