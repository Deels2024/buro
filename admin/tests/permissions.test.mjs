import assert from "node:assert/strict";
import test from "node:test";
import { canAccessSection } from "../app/lib/permissions.ts";

test("moderators only see their operational sections", () => {
  for (const section of ["items", "claims", "matches", "moderation", "support"]) {
    assert.equal(canAccessSection("moderator", section), true);
    assert.equal(canAccessSection("admin", section), true);
    for (const role of ["user", "operator", "manager", "", "unknown"]) {
      assert.equal(canAccessSection(role, section), false);
    }
  }
  for (const section of ["overview", "organizations", "users", "integrations", "analytics", "settings"]) {
    assert.equal(canAccessSection("moderator", section), false);
    assert.equal(canAccessSection("admin", section), true);
  }
  assert.equal(canAccessSection("admin", "unknown"), false);
});
