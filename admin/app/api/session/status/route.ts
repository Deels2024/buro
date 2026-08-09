import { NextResponse } from "next/server";
import { authenticatedFetch, clearSession } from "@/app/lib/backend";

export async function GET() {
  const response = await authenticatedFetch("/users/me");
  if (!response.ok) {
    await clearSession();
    return NextResponse.json({ authenticated: false }, { status: 401 });
  }
  const user = await response.json() as { role?: string };
  if (!user.role || !["admin", "moderator"].includes(user.role)) {
    await clearSession();
    return NextResponse.json({ authenticated: false, detail: "Недостаточно прав" }, { status: 403 });
  }
  return NextResponse.json({ authenticated: true, user });
}
