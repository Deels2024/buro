import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { act, create } from "react-test-renderer";
import components from "./load-components.mjs";

test("section changes clear old row types and ignore late responses", async () => {
  const originalFetch = globalThis.fetch;
  const originalWindow = globalThis.window;
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  globalThis.window = { setTimeout, clearTimeout, addEventListener() {}, removeEventListener() {} };
  let resolveMatches;
  const user = { id: "test-user", role: "admin", display_name: "Тестовый сотрудник", phone_masked: "Скрыт" };
  globalThis.fetch = async (url) => {
    let data = { items: [], total: 0 };
    if (url.includes("/analytics/overview")) data = { kpi: {}, funnel: [], series: [], operations: {}, categories: [], regions: [] };
    if (url.includes("/dashboard")) data = {};
    if (url.includes("/admin/settings")) data = [];
    if (url.includes("/users?")) data = { items: [{ ...user, status: "active", created_at: "2026-01-01" }], total: 1 };
    if (url.includes("/matches?")) return new Promise(resolve => { resolveMatches = resolve; });
    if (url.includes("/support/tickets")) data = { items: [{ id: "ticket", subject: "Обращение с длинным названием", status: "open", updated_at: "2026-01-01" }], total: 1 };
    return { ok: true, json: async () => data };
  };
  let tree;
  const settle = () => act(async () => { await new Promise(resolve => setTimeout(resolve, 260)); });
  const click = async (label) => act(async () => {
    const button = tree.root.findAllByType("button").find(node => node.findAllByType("span").some(span => span.children.includes(label)));
    assert.ok(button, label);
    button.props.onClick();
  });
  try {
    await act(async () => { tree = create(React.createElement(components.AdminConsole, { user, onLogout() {} })); });
    await settle();
    await click("Пользователи");
    await settle();
    assert.equal(tree.root.findAllByProps({ className: "user-card" }).length, 1);
    await click("ИИ-совпадения");
    // Before the new request resolves, user rows must not reach Matches.
    assert.equal(tree.root.findAllByProps({ className: "match-card" }).length, 0);
    await settle();
    assert.equal(typeof resolveMatches, "function");
    await click("Поддержка");
    await settle();
    await act(async () => resolveMatches({ ok: true, json: async () => ({ items: [{ id: "late-match", score: 85 }], total: 1 }) }));
    const tickets = tree.root.findAllByProps({ className: "ticket-copy" });
    assert.equal(tickets.length, 1);
    assert.ok(JSON.stringify(tickets[0].children[0].children).includes("Обращение с длинным названием"));
    await click("Настройки");
    await settle();
  } finally {
    if (tree) await act(async () => tree.unmount());
    globalThis.fetch = originalFetch;
    globalThis.window = originalWindow;
    delete globalThis.IS_REACT_ACT_ENVIRONMENT;
  }
});
