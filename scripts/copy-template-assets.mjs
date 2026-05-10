import { cp, mkdir } from "node:fs/promises";

await mkdir("dist/core/templates/defaults", { recursive: true });
await cp("src/core/templates/defaults", "dist/core/templates/defaults", { recursive: true });
