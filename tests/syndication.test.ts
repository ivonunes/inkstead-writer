import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import sharp from "sharp";
import { updateSyndicationFrontmatter } from "../src/index.js";
import { prepareImageForSyndication } from "../src/core/syndication/media.js";
import { useSiteFixture } from "./helpers/site.js";

const fixture = useSiteFixture();

describe("frontmatter syndication", () => {
  it("prepares oversized images for syndication without changing the original", async () => {
    const source = path.join(fixture.tempRoot, "large.png");
    const original = await sharp({
      create: {
        width: 1200,
        height: 1200,
        channels: 3,
        background: "#5fc9b5"
      }
    }).png().toBuffer();
    await fs.writeFile(source, original);

    const prepared = await prepareImageForSyndication(source, { maxBytes: 20_000, maxDimension: 800 });
    expect(prepared.generated).toBe(true);
    expect(prepared.mimeType).toBe("image/jpeg");
    expect(prepared.bytes.byteLength).toBeLessThanOrEqual(20_000);
    expect(await fs.readFile(source)).toEqual(original);
  });

  it("uses the original image when it already fits syndication limits", async () => {
    const source = path.join(fixture.tempRoot, "small.jpg");
    const original = await sharp({
      create: {
        width: 64,
        height: 64,
        channels: 3,
        background: "#f7b733"
      }
    }).jpeg().toBuffer();
    await fs.writeFile(source, original);

    const prepared = await prepareImageForSyndication(source, { maxBytes: 100_000, maxDimension: 800 });
    expect(prepared.generated).toBe(false);
    expect(prepared.path).toBe(source);
    expect(prepared.bytes).toEqual(original);
  });

  it("updates only syndication data and preserves the markdown body", () => {
    const original = "---\ndate: 2026-05-10T18:30:00+01:00\nsyndicate:\n  - mastodon\n---\n\nBody **must** stay.\n\n";
    const updated = updateSyndicationFrontmatter(original, "mastodon", { status: "published", url: "https://example.com/1" });
    expect(updated).toContain("syndication:");
    expect(updated).toContain("mastodon:");
    expect(updated.endsWith("\nBody **must** stay.\n")).toBe(true);
  });

  it("can represent already published targets for idempotent syndication", () => {
    const updated = updateSyndicationFrontmatter("---\ndate: 2026-05-10T18:30:00+01:00\n---\n\nHi\n", "bluesky", { status: "published", uri: "at://did/post" });
    expect(updated).toContain("status: published");
    expect(updated).toContain("at://did/post");
  });
});
