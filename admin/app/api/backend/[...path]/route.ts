import { NextResponse } from "next/server";
import { assertSameOrigin, authenticatedFetch, relay } from "@/app/lib/backend";

type Context = { params: Promise<{ path: string[] }> };

async function proxy(request: Request, context: Context) {
  try {
    await assertSameOrigin(request);
    const { path } = await context.params;
    if (!path.length || path.some((part) => part === ".." || part.includes("/"))) {
      return NextResponse.json({ detail: "Недопустимый путь API" }, { status: 400 });
    }
    const url = new URL(request.url);
    const target = `/${path.map(encodeURIComponent).join("/")}${url.search}`;
    const headers = new Headers();
    for (const name of ["content-type", "accept", "idempotency-key", "x-request-id"]) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    const hasBody = !["GET", "HEAD"].includes(request.method);
    const body = hasBody ? await request.arrayBuffer() : undefined;
    return relay(await authenticatedFetch(target, { method: request.method, headers, body }));
  } catch (error) {
    return NextResponse.json({ detail: error instanceof Error ? error.message : "Ошибка API" }, { status: 500 });
  }
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
