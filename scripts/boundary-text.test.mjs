import assert from "node:assert/strict";
import test from "node:test";
import { normalizeBoundaryText } from "./boundary-text.mjs";

test("normalizes encoded and case-varied browser boundary markers", () => {
  for (const value of [
    "/ARC/README.md",
    "/%61rc/README.md",
    "./&#97;rc/README.md",
    "./\\x61rc/README.md",
  ]) {
    assert.match(normalizeBoundaryText(value), /arc\/readme\.md/);
  }

  for (const value of [
    "/docs/research/recent%2Dchats%2D2026%2D08%2D29/manifest.json",
    "/docs/research/recent-&#99;hats-2026-08-29/README.md",
    "/DOCS/RESEARCH/RECENT-CHATS-2026-08-29/README.md",
  ]) {
    assert.match(normalizeBoundaryText(value), /recent-chats-2026-08-29/);
  }
});
