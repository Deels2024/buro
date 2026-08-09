import { cookies, headers } from "next/headers";

const ACCESS_COOKIE = "bn_admin_access";
const REFRESH_COOKIE = "bn_admin_refresh";
const MFA_COOKIE = "bn_admin_mfa";

type TokenPair = {
  access_token: string;
  refresh_token: string;
  token_type: "bearer";
  expires_in: number;
};

function baseUrl() {
  return (process.env.BUREAU_API_URL ?? "http://api:8080/v1").replace(/\/$/, "");
}

function cookieOptions(maxAge: number) {
  return {
    httpOnly: true,
    sameSite: "strict" as const,
    secure: process.env.ADMIN_COOKIE_SECURE === "true",
    path: "/",
    maxAge,
  };
}

export async function assertSameOrigin(request: Request) {
  if (["GET", "HEAD", "OPTIONS"].includes(request.method)) return;
  const origin = request.headers.get("origin");
  if (!origin) return;
  const requestHeaders = await headers();
  const expectedHost = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  if (!expectedHost || new URL(origin).host !== expectedHost) {
    throw new Error("Недопустимый источник запроса");
  }
}

export async function backendFetch(path: string, init: RequestInit = {}) {
  return fetch(`${baseUrl()}${path.startsWith("/") ? path : `/${path}`}`, {
    ...init,
    cache: "no-store",
  });
}

export async function setSession(tokens: TokenPair) {
  const store = await cookies();
  store.set(ACCESS_COOKIE, tokens.access_token, cookieOptions(tokens.expires_in));
  store.set(REFRESH_COOKIE, tokens.refresh_token, cookieOptions(30 * 24 * 60 * 60));
  store.delete(MFA_COOKIE);
}

export async function setMfaTicket(ticket: string, expiresIn = 300) {
  const store = await cookies();
  store.set(MFA_COOKIE, ticket, cookieOptions(expiresIn));
}

export async function getMfaTicket() {
  return (await cookies()).get(MFA_COOKIE)?.value ?? null;
}

export async function clearSession() {
  const store = await cookies();
  store.delete(ACCESS_COOKIE);
  store.delete(REFRESH_COOKIE);
  store.delete(MFA_COOKIE);
}

async function refreshSession() {
  const store = await cookies();
  const refreshToken = store.get(REFRESH_COOKIE)?.value;
  if (!refreshToken) return null;
  const response = await backendFetch("/auth/refresh", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken, device_name: "Web admin" }),
  });
  if (!response.ok) {
    await clearSession();
    return null;
  }
  const tokens = (await response.json()) as TokenPair;
  await setSession(tokens);
  return tokens.access_token;
}

export async function authenticatedFetch(path: string, init: RequestInit = {}) {
  const store = await cookies();
  let accessToken = store.get(ACCESS_COOKIE)?.value;
  if (!accessToken) accessToken = await refreshSession() ?? undefined;
  if (!accessToken) return new Response(JSON.stringify({ detail: "Нужна авторизация" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });

  const makeRequest = (token: string) => {
    const requestHeaders = new Headers(init.headers);
    requestHeaders.set("Authorization", `Bearer ${token}`);
    return backendFetch(path, { ...init, headers: requestHeaders });
  };

  let response = await makeRequest(accessToken);
  if (response.status === 401) {
    const refreshed = await refreshSession();
    if (!refreshed) return response;
    response = await makeRequest(refreshed);
  }
  return response;
}

export async function relay(response: Response) {
  const headers = new Headers();
  for (const name of ["content-type", "content-disposition", "x-request-id"]) {
    const value = response.headers.get(name);
    if (value) headers.set(name, value);
  }
  return new Response(response.body, { status: response.status, headers });
}

export async function verifyAdminAccess(accessToken: string) {
  const response = await backendFetch("/users/me", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) return { ok: false as const, response };
  const user = await response.json() as { role?: string };
  if (!user.role || !["admin", "moderator"].includes(user.role)) {
    return {
      ok: false as const,
      response: new Response(JSON.stringify({ detail: "Доступ разрешён только администраторам" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      }),
    };
  }
  return { ok: true as const, user };
}

export type { TokenPair };
