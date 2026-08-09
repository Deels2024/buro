export type TokenPair = {
  access_token: string;
  refresh_token: string;
  token_type: "bearer";
  expires_in: number;
};

export type Page<T> = { items: T[]; total: number; limit: number; offset: number };

export class BureauApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly detail: string,
    public readonly requestId?: string,
  ) {
    super(detail);
  }
}

type TokenStore = {
  get: () => TokenPair | null;
  set: (tokens: TokenPair | null) => void;
};

export class BureauApi {
  private refreshPromise: Promise<TokenPair> | null = null;

  constructor(
    private readonly baseUrl: string,
    private readonly tokenStore: TokenStore,
  ) {}

  private async refresh(): Promise<TokenPair> {
    const current = this.tokenStore.get();
    if (!current) throw new BureauApiError(401, "Сессия отсутствует");
    if (!this.refreshPromise) {
      this.refreshPromise = fetch(`${this.baseUrl}/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: current.refresh_token }),
      })
        .then(async (response) => {
          if (!response.ok) {
            this.tokenStore.set(null);
            throw new BureauApiError(response.status, "Сессия истекла");
          }
          const tokens = (await response.json()) as TokenPair;
          this.tokenStore.set(tokens);
          return tokens;
        })
        .finally(() => {
          this.refreshPromise = null;
        });
    }
    return this.refreshPromise;
  }

  async request<T>(
    path: string,
    init: RequestInit = {},
    options: { auth?: boolean; retry401?: boolean; idempotencyKey?: string } = {},
  ): Promise<T> {
    const auth = options.auth ?? true;
    const headers = new Headers(init.headers);
    if (!headers.has("Content-Type") && init.body) headers.set("Content-Type", "application/json");
    const tokens = this.tokenStore.get();
    if (auth && tokens) headers.set("Authorization", `Bearer ${tokens.access_token}`);
    if (options.idempotencyKey) headers.set("Idempotency-Key", options.idempotencyKey);
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers });
    if (response.status === 401 && auth && (options.retry401 ?? true) && tokens) {
      await this.refresh();
      return this.request<T>(path, init, { ...options, retry401: false });
    }
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new BureauApiError(
        response.status,
        typeof body.detail === "string" ? body.detail : "Ошибка API",
        response.headers.get("X-Request-ID") ?? undefined,
      );
    }
    if (response.status === 204) return undefined as T;
    return (await response.json()) as T;
  }

  bootstrap = () => this.request<Record<string, unknown>>("/app/bootstrap", {}, { auth: false });

  requestCode = (phone: string) =>
    this.request<{ expires_in: number; retry_after: number; dev_code?: string }>(
      "/auth/request-code",
      { method: "POST", body: JSON.stringify({ phone }) },
      { auth: false },
    );

  verifyCode = (phone: string, code: string, deviceName = "Web admin") =>
    this.request<TokenPair | { mfa_required: true; mfa_ticket: string; expires_in: number }>(
      "/auth/verify-code",
      { method: "POST", body: JSON.stringify({ phone, code, device_name: deviceName }) },
      { auth: false },
    );

  verifyAdmin2FA = (mfaTicket: string, code: string) =>
    this.request<TokenPair>(
      "/auth/verify-admin-2fa",
      { method: "POST", body: JSON.stringify({ mfa_ticket: mfaTicket, code, device_name: "Web admin" }) },
      { auth: false },
    ).then((tokens) => {
      this.tokenStore.set(tokens);
      return tokens;
    });

  me = () => this.request<Record<string, unknown>>("/users/me");
  dashboard = () => this.request<Record<string, number>>("/admin/dashboard");

  analytics = (params: URLSearchParams) =>
    this.request<Record<string, unknown>>(`/admin/analytics/overview?${params}`);

  users = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/users?${params}`);

  updateUser = (id: string, payload: { role?: string; status?: string }) =>
    this.request<Record<string, unknown>>(`/admin/users/${id}`, {
      method: "PATCH",
      body: JSON.stringify(payload),
    });

  organizations = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/organizations?${params}`);

  listings = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/listings?${params}`);

  claims = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/claims?${params}`);

  matches = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/matches?${params}`);

  handovers = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/handovers?${params}`);

  supportTickets = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/support/tickets?${params}`);

  updateSupportTicket = (id: string, payload: Record<string, unknown>) =>
    this.request<Record<string, unknown>>(`/admin/support/tickets/${id}`, {
      method: "PATCH",
      body: JSON.stringify(payload),
    });

  audit = (params = new URLSearchParams()) =>
    this.request<Page<Record<string, unknown>>>(`/admin/audit?${params}`);

  settings = () => this.request<Array<Record<string, unknown>>>("/admin/settings");

  updateSetting = (key: string, payload: Record<string, unknown>) =>
    this.request<Record<string, unknown>>(`/admin/settings/${encodeURIComponent(key)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
}
