import { NextResponse } from "next/server";
import { assertSameOrigin, backendFetch, relay } from "@/app/lib/backend";

export async function POST(request: Request) {
  try {
    await assertSameOrigin(request);
    const body = await request.text();
    return relay(await backendFetch("/auth/request-code", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    }));
  } catch (error) {
    return NextResponse.json({ detail: error instanceof Error ? error.message : "Ошибка запроса" }, { status: 400 });
  }
}
