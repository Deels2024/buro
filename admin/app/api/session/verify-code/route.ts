import { NextResponse } from "next/server";
import {
  assertSameOrigin,
  backendFetch,
  clearSession,
  setMfaTicket,
  setSession,
  TokenPair,
  verifyAdminAccess,
} from "@/app/lib/backend";

export async function POST(request: Request) {
  try {
    await assertSameOrigin(request);
    const response = await backendFetch("/auth/verify-code", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: await request.text(),
    });
    const data = await response.json().catch(() => ({ detail: "Ошибка авторизации" }));
    if (!response.ok) return NextResponse.json(data, { status: response.status });
    if (data.mfa_required) {
      await setMfaTicket(data.mfa_ticket, data.expires_in);
      return NextResponse.json({ mfa_required: true, expires_in: data.expires_in });
    }
    const tokens = data as TokenPair;
    const access = await verifyAdminAccess(tokens.access_token);
    if (!access.ok) {
      await clearSession();
      return new NextResponse(access.response.body, {
        status: access.response.status,
        headers: { "Content-Type": "application/json" },
      });
    }
    await setSession(tokens);
    return NextResponse.json({ authenticated: true, user: access.user });
  } catch (error) {
    return NextResponse.json({ detail: error instanceof Error ? error.message : "Ошибка авторизации" }, { status: 400 });
  }
}
