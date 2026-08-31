import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
const proxy = await readFile(new URL("../app/api/backend/[...path]/route.ts", import.meta.url), "utf8");
const session = await readFile(new URL("../app/lib/backend.ts", import.meta.url), "utf8");
const layout = await readFile(new URL("../app/layout.tsx", import.meta.url), "utf8");
const robots = await readFile(new URL("../app/robots.ts", import.meta.url), "utf8");

test("admin sections use backend endpoints", () => {
  for (const path of [
    "/admin/analytics/overview",
    "/admin/listings",
    "/admin/claims",
    "/admin/matches",
    "/admin/organizations",
    "/admin/users",
    "/admin/support/tickets",
    "/admin/settings",
  ]) assert.ok(page.includes(path), path);
});

test("browser tokens are kept in HttpOnly cookies", () => {
  assert.match(session, /httpOnly:\s*true/);
  assert.doesNotMatch(page, /localStorage|sessionStorage|access_token|refresh_token/);
});

test("authenticated proxy forwards all required methods", () => {
  for (const method of ["GET", "POST", "PUT", "PATCH", "DELETE"]) {
    assert.ok(proxy.includes("export const " + method + " = proxy"), method);
  }
});

test("new finding is saved as a valid draft until a photo is uploaded", () => {
  assert.match(page, /media_ids:\s*\[\],\s*storage_code:[^\n]+publish:\s*false/);
  assert.doesNotMatch(page, /media_ids:\s*\[\],\s*storage_code:[^\n]+publish:\s*true/);
});

test("admin interface is excluded from search indexing", () => {
  assert.match(layout, /robots:\s*\{/);
  assert.match(layout, /index:\s*false/);
  assert.match(layout, /follow:\s*false/);
  assert.match(robots, /disallow:\s*["']\/["']/);
});
