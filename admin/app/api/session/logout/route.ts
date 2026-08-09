import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { assertSameOrigin, backendFetch, clearSession } from "@/app/lib/backend";

export async function POST(request: Request) {
  try {
    await assertSameOrigin(request);
    const store = await cookies();
    const refreshToken = store.get("bn_admin_refresh")?.value;
    const accessToken = store.get("bn_admin_access")?.value;
    if (refreshToken && accessToken) {
      await backendFetch("/auth/logout", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });
    }
  } finally {
    await clearSession();
  }
  return NextResponse.json({ authenticated: false });
}
