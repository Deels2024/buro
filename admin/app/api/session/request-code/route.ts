import { NextResponse } from "next/server";
import { assertSameOrigin, backendFetch, relay } from "@/app/lib/backend";

export async function POST(request: Request) {
  try {
    await assertSameOrigin(request);
    const body = await request.text();
    const headers = new Headers({ "Content-Type": "application/json" });
    const clientIp = request.headers.get("x-real-ip");
    if (clientIp) headers.set("X-Real-IP", clientIp);
    return relay(await backendFetch("/auth/request-code", {
      method: "POST",
      headers,
      body,
    }));
  } catch (error) {
    return NextResponse.json({ detail: error instanceof Error ? error.message : "Ошибка запроса" }, { status: 400 });
  }
}
