import { createHash } from "node:crypto";

type RefreshResult = {
  access_token: string;
  refresh_token: string;
  token_type: "bearer";
  expires_in: number;
} | null;

// The current deployment has one Next.js process. Parallel dashboard requests
// must share one rotation and receive the same new cookies. A short grace
// period also covers requests that arrived with the old cookie mid-rotation.
const pending = new Map<string, Promise<RefreshResult>>();

export function coalesceRefresh(token: string, load: () => Promise<RefreshResult>) {
  const key = createHash("sha256").update(token).digest("hex");
  const existing = pending.get(key);
  if (existing) return existing;
  const promise = Promise.resolve().then(load);
  pending.set(key, promise);
  const clear = () => {
    const timer = setTimeout(() => pending.delete(key), 5000);
    timer.unref();
  };
  void promise.then(clear, () => pending.delete(key));
  return promise;
}
