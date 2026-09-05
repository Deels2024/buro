import assert from "node:assert/strict";
import test from "node:test";
import { coalesceRefresh } from "../app/lib/refresh.ts";

test("concurrent dashboard requests rotate once and share new cookies", async () => {
  let calls = 0;
  const tokens = { access_token: "new-access", refresh_token: "new-refresh", token_type: "bearer", expires_in: 900 };
  const load = async () => { calls++; await new Promise(resolve => setTimeout(resolve, 10)); return tokens; };
  const responses = await Promise.all(Array.from({ length: 20 }, () => coalesceRefresh("same-session", load)));
  assert.equal(calls, 1);
  assert.ok(responses.every(value => value === tokens));
  assert.equal(await coalesceRefresh("same-session", load), tokens);
  assert.equal(calls, 1);
});

test("different users do not share a rotated session", async () => {
  const first = { access_token: "first", refresh_token: "first", token_type: "bearer", expires_in: 900 };
  const second = { ...first, access_token: "second" };
  const values = await Promise.all([coalesceRefresh("user-a", async () => first), coalesceRefresh("user-b", async () => second)]);
  assert.deepEqual(values, [first, second]);
});

test("temporary provider failure can be retried", async () => {
  await assert.rejects(coalesceRefresh("temporary-failure", async () => { throw new Error("unavailable"); }));
  assert.equal(await coalesceRefresh("temporary-failure", async () => null), null);
});
