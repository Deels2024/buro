import { NextResponse } from "next/server";
import {
  assertSameOrigin,
  backendFetch,
  clearSession,
  getMfaTicket,
  setSession,
  TokenPair,
  verifyAdminAccess,
} from "@/app/lib/backend";

export async function POST(request: Request) {
  try {
    await assertSameOrigin(request);
    const ticket = await getMfaTicket();
    if (!ticket) return NextResponse.json({ detail: "Проверка 2FA истекла" }, { status: 401 });
    const payload = await request.json() as { code?: string };
    const response = await backendFetch("/auth/verify-admin-2fa", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mfa_ticket: ticket, code: payload.code, device_name: "Web admin" }),
    });
    const data = await response.json().catch(() => ({ detail: "Ошибка 2FA" }));
    if (!response.ok) return NextResponse.json(data, { status: response.status });
    const tokens = data as TokenPair;
    const access = await verifyAdminAccess(tokens.access_token);
    if (!access.ok) {
      await clearSession();
      return NextResponse.json({ detail: "Недостаточно прав" }, { status: 403 });
    }
    await setSession(tokens);
    return NextResponse.json({ authenticated: true, user: access.user });
  } catch (error) {
    return NextResponse.json({ detail: error instanceof Error ? error.message : "Ошибка 2FA" }, { status: 400 });
  }
}
