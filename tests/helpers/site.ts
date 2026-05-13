import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { beforeEach } from "vitest";
import { initSite } from "../../src/index.js";

export interface SiteFixture {
  readonly tempRoot: string;
  makeSite(): Promise<string>;
}

export function useSiteFixture(): SiteFixture {
  let tempRoot = "";

  beforeEach(async () => {
    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "inkstead-test-"));
  });

  async function makeSite(): Promise<string> {
    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "inkstead-test-"));
    const cwd = process.cwd();
    process.chdir(tempRoot);
    try {
      await initSite("site");
    } finally {
      process.chdir(cwd);
    }
    return path.join(tempRoot, "site");
  }

  return {
    get tempRoot() {
      return tempRoot;
    },
    makeSite
  };
}
