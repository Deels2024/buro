"use client";

import { MediaGallery, OperationalDrawer, TrafficCounts } from "./operations";

import { FormEvent, ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";

type NavKey =
  | "overview"
  | "items"
  | "claims"
  | "matches"
  | "organizations"
  | "users"
  | "moderation"
  | "support"
  | "integrations"
  | "analytics"
  | "settings";

type PageResponse<T> = { items: T[]; total: number; limit: number; offset: number };
type SessionUser = { id: string; display_name: string; role: string; phone_masked: string };
type AnalyticsData = {
  period: { from: string; to: string; granularity: string };
  kpi: Record<string, number>;
  funnel: { stage: string; value: number }[];
  series: { date: string; lost: number; found: number }[];
  categories: { name: string | null; value: number }[];
  regions: { name: string | null; value: number }[];
  operations: { support_open: number; webhook_queue: number; webhook_failures: number };
};
type ListingRow = {
  id: string; title: string; kind: string; category: string; region: string;
  status: string; moderation_status: string; organization_id: string | null; created_at: string;
};
type ClaimRow = {
  id: string; listing_id: string; claimant_id: string; status: string;
  risk_score: number; risk_factors: string[]; submitted_at: string | null; created_at: string;
};
type MatchRow = {
  id: string; source_listing_id: string; candidate_listing_id: string;
  score: number; factors: Record<string, number>; status: string; created_at: string;
};
type OrganizationRow = {
  id: string; name: string; inn: string; status: string; api_enabled: boolean;
  inventory: number; webhooks: number; created_at: string;
};
type UserRow = {
  id: string; display_name: string; phone_masked: string; role: string; status: string;
  admin_2fa_enabled: boolean; verified_at: string | null; last_seen_at: string | null; created_at: string;
};
type ModerationRow = { id: string; title: string; description: string; kind: string; category: string; created_at: string; media: { id: string; download_url: string; mime_type: string; status: string }[] };
type TicketRow = {
  id: string; subject: string; category: string; priority: string; status: string;
  assigned_to: string | null; created_at: string; updated_at: string;
};
type AuditRow = {
  id: string; action: string; entity_type: string; entity_id: string | null;
  payload: Record<string, unknown>; created_at: string;
};
type SettingRow = {
  key: string; value: Record<string, unknown>; description: string; public: boolean; updated_at: string;
};
type Health = { status: string; database: string; redis: string; version: string };

const navigation: { key: NavKey; label: string; icon: string }[] = [
  { key: "overview", label: "Главная", icon: "⌂" },
  { key: "items", label: "Публикации", icon: "◇" },
  { key: "claims", label: "Заявки о пропаже", icon: "⌕" },
  { key: "matches", label: "ИИ-совпадения", icon: "✦" },
  { key: "organizations", label: "Организации", icon: "▦" },
  { key: "users", label: "Пользователи", icon: "◎" },
  { key: "moderation", label: "Модерация", icon: "✓" },
  { key: "support", label: "Поддержка", icon: "◌" },
  { key: "integrations", label: "Интеграции", icon: "↔" },
  { key: "analytics", label: "Аналитика", icon: "↗" },
  { key: "settings", label: "Настройки", icon: "⚙" },
];

const sectionTitles: Record<NavKey, { title: string; subtitle: string }> = {
  overview: { title: "Операционный центр", subtitle: "Живые данные всей сети" },
  items: { title: "Реестр публикаций", subtitle: "Пропажи и находки пользователей и организаций" },
  claims: { title: "Заявки о пропаже", subtitle: "Единая очередь обращений пользователей" },
  matches: { title: "ИИ-совпадения", subtitle: "Проверка рекомендаций и подтверждение совпадений" },
  organizations: { title: "Организации", subtitle: "Партнёры, API и объём реестра" },
  users: { title: "Пользователи", subtitle: "Роли, статусы и безопасность аккаунтов" },
  moderation: { title: "Модерация", subtitle: "Очередь карточек, требующих решения" },
  support: { title: "Поддержка", subtitle: "Обращения пользователей и организаций" },
  integrations: { title: "Интеграции", subtitle: "Состояние backend, базы, Redis и вебхуков" },
  analytics: { title: "Полная аналитика", subtitle: "Воронка, динамика, категории и география" },
  settings: { title: "Настройки проекта", subtitle: "Параметры поиска, хранения и поддержки" },
};

const statusNames: Record<string, string> = {
  active: "Активно", draft: "Черновик", paused: "Приостановлено", closed: "Закрыто",
  approved: "Подтверждено", rejected: "Отклонено", under_review: "На проверке",
  needs_more_info: "Нужно уточнение", pending: "Ожидает", verified: "Проверена",
  blocked: "Заблокировано", accepted: "Принято", hidden: "Скрыто", open: "Открыто",
  in_progress: "В работе", waiting_user: "Ожидает пользователя", resolved: "Решено",
  normal: "Обычный", high: "Высокий", urgent: "Срочный", low: "Низкий",
};

function statusName(value: string) {
  return statusNames[value] ?? value;
}

function statusTone(value: string) {
  if (["approved", "verified", "accepted", "active", "resolved", "ready"].includes(value)) return "green";
  if (["rejected", "blocked", "failed", "urgent"].includes(value)) return "red";
  if (["pending", "under_review", "needs_more_info", "high", "waiting_user"].includes(value)) return "amber";
  return "blue";
}

function formatDate(value?: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function number(value?: number) {
  return new Intl.NumberFormat("ru-RU").format(value ?? 0);
}

async function jsonRequest<T>(url: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const response = await fetch(url, { ...init, headers, cache: "no-store" });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = typeof data.detail === "string" ? data.detail : "Ошибка сервера";
    throw new Error(detail);
  }
  return data as T;
}

function Status({ children, tone = "gray" }: { children: ReactNode; tone?: string }) {
  return <span className={"status status-" + tone}><i />{children}</span>;
}

function Login({ onDone }: { onDone: (user: SessionUser) => void }) {
  const [step, setStep] = useState<"phone" | "code" | "mfa">("phone");
  const [phone, setPhone] = useState("+7");
  const [code, setCode] = useState("");
  const [devCode, setDevCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (step === "phone") {
        const result = await jsonRequest<{ dev_code?: string }>("/api/session/request-code", {
          method: "POST", body: JSON.stringify({ phone }),
        });
        setDevCode(result.dev_code ?? "");
        setCode(result.dev_code ?? "");
        setStep("code");
      } else if (step === "code") {
        const result = await jsonRequest<{ authenticated?: boolean; mfa_required?: boolean; user?: SessionUser }>("/api/session/verify-code", {
          method: "POST", body: JSON.stringify({ phone, code, device_name: "Web admin" }),
        });
        if (result.mfa_required) setStep("mfa");
        else if (result.user) onDone(result.user);
      } else {
        const result = await jsonRequest<{ user: SessionUser }>("/api/session/verify-2fa", {
          method: "POST", body: JSON.stringify({ code }),
        });
        onDone(result.user);
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Не удалось войти");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-shell">
      <section className="login-card">
        <div className="login-brand"><span className="brand-mark">БН</span><div><strong>Бюро находок</strong><small>защищённая веб-админка</small></div></div>
        <div className="login-copy">
          <Status tone="green">Backend подключён</Status>
          <h1>{step === "phone" ? "Вход администратора" : step === "code" ? "Введите код из SMS" : "Двухфакторная проверка"}</h1>
          <p>{step === "phone" ? "Используйте номер администратора, указанный при установке." : step === "code" ? "Код действует пять минут." : "Введите одноразовый код из приложения-аутентификатора."}</p>
        </div>
        <form onSubmit={submit} className="login-form">
          {step === "phone" ? (
            <label><span>Номер телефона</span><input value={phone} onChange={(event) => setPhone(event.target.value)} autoComplete="tel" required /></label>
          ) : (
            <label><span>{step === "mfa" ? "Код 2FA" : "Код подтверждения"}</span><input value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))} inputMode="numeric" pattern="\d{6}" autoFocus required /></label>
          )}
          {devCode && step === "code" && <div className="dev-code">Код для локального запуска: <strong>{devCode}</strong></div>}
          {error && <div className="form-error">{error}</div>}
          <button className="primary-button login-submit" disabled={busy}>{busy ? "Проверяем…" : step === "phone" ? "Получить код" : "Войти"}</button>
          {step !== "phone" && <button type="button" className="text-button" onClick={() => { setStep("phone"); setCode(""); setError(""); }}>Изменить номер</button>}
        </form>
        <small className="security-note">Сессия хранится в защищённых HttpOnly cookies. Токены недоступны коду браузера.</small>
      </section>
    </main>
  );
}

function KpiCard({ label, value, note, color = "teal" }: { label: string; value: string; note: string; color?: string }) {
  return <article className="kpi-card"><div className={"kpi-icon " + color}>{label.slice(0, 1)}</div><div className="kpi-main"><p>{label}</p><strong>{value}</strong><span>{note}</span></div></article>;
}

function Dashboard({ analytics, dashboard, audit, onNavigate }: {
  analytics: AnalyticsData | null; dashboard: Record<string, number>; audit: AuditRow[]; onNavigate: (key: NavKey) => void;
}) {
  const kpi = analytics?.kpi ?? {};
  const funnelMax = Math.max(...(analytics?.funnel.map((item) => item.value) ?? [1]), 1);
  const series = analytics?.series ?? [];
  const seriesMax = Math.max(...series.map((item) => item.lost + item.found), 1);
  return (
    <>
      <section className="kpi-grid">
        <KpiCard label="Находок за период" value={number(kpi.found)} note="из реальной базы" />
        <KpiCard label="Заявлений" value={number(kpi.claims)} note="за выбранный период" color="blue" />
        <KpiCard label="Возвращено" value={number(kpi.returned)} note="подтвержденных выдач" color="violet" />
        <KpiCard label="Доля возврата" value={(kpi.return_rate ?? 0).toFixed(1) + "%"} note="от найденных вещей" color="amber" />
      </section>
      <section className="dashboard-grid">
        <article className="panel trend-panel">
          <div className="panel-head"><div><h2>Динамика публикаций</h2><p>Потеряно и найдено по дням</p></div><Status tone="green">Live API</Status></div>
          <div className="live-bars">
            {series.length ? series.map((item) => <div key={item.date} title={formatDate(item.date) + ": " + (item.lost + item.found)}><i style={{ height: Math.max(6, ((item.lost + item.found) / seriesMax) * 100) + "%" }} /><span>{new Date(item.date).getDate()}</span></div>) : <div className="empty-inline">Данные появятся после первых операций</div>}
          </div>
        </article>
        <article className="panel funnel-panel">
          <div className="panel-head"><div><h2>Воронка возврата</h2><p>Рассчитана backend</p></div></div>
          <div className="funnel">{(analytics?.funnel ?? []).map((item) => <div className="funnel-row" key={item.stage}><div><span>{item.stage}</span><strong>{number(item.value)}</strong></div><div className="progress"><i className="teal" style={{ width: ((item.value / funnelMax) * 100) + "%" }} /></div></div>)}</div>
        </article>
      </section>
      <section className="dashboard-grid lower">
        <article className="panel">
          <div className="panel-head"><div><h2>Очереди операций</h2><p>То, что требует внимания команды</p></div></div>
          <div className="operations-grid">
            <button onClick={() => onNavigate("moderation")}><strong>{dashboard.pending_listings ?? 0}</strong><span>карточек на модерации</span></button>
            <button onClick={() => onNavigate("claims")}><strong>{dashboard.risky_claims ?? 0}</strong><span>рисковых заявлений</span></button>
            <button onClick={() => onNavigate("organizations")}><strong>{dashboard.pending_organizations ?? 0}</strong><span>организаций на проверке</span></button>
            <button onClick={() => onNavigate("support")}><strong>{analytics?.operations.support_open ?? 0}</strong><span>обращений поддержки</span></button>
          </div>
        </article>
        <article className="panel">
          <div className="panel-head"><div><h2>Последние действия</h2><p>Неизменяемый журнал аудита</p></div></div>
          <div className="compact-list">{audit.length ? audit.slice(0, 5).map((item) => <div key={item.id}><Status tone="blue">{item.entity_type}</Status><span><strong>{item.action}</strong><small>{formatDate(item.created_at)}</small></span></div>) : <div className="empty-inline">Журнал пока пуст</div>}</div>
        </article>
      </section>
    </>
  );
}

function DataTable({ children }: { children: ReactNode }) {
  return <section className="panel registry-panel">{children}</section>;
}

function AdminConsole({ user, onLogout }: { user: SessionUser; onLogout: () => void }) {
  const [section, setSection] = useState<NavKey>("overview");
  const [query, setQuery] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [analytics, setAnalytics] = useState<AnalyticsData | null>(null);
  const [dashboard, setDashboard] = useState<Record<string, number>>({});
  const [records, setRecords] = useState<unknown[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [audit, setAudit] = useState<AuditRow[]>([]);
  const [health, setHealth] = useState<Health | null>(null);
  const [selected, setSelected] = useState<Record<string, unknown> | null>(null);
  const [addOpen, setAddOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  const loadSummary = useCallback(async () => {
    const [analyticsResult, dashboardResult, auditResult] = await Promise.all([
      jsonRequest<AnalyticsData>("/api/backend/admin/analytics/overview?granularity=day"),
      jsonRequest<Record<string, number>>("/api/backend/admin/dashboard"),
      jsonRequest<PageResponse<AuditRow>>("/api/backend/admin/audit?limit=10"),
    ]);
    setAnalytics(analyticsResult);
    setDashboard(dashboardResult);
    setAudit(auditResult.items);
  }, []);

  const loadSection = useCallback(async (key: NavKey, search: string) => {
    setLoading(true);
    setError("");
    try {
      if (key === "overview" || key === "analytics") {
        await loadSummary();
        setRecords([]);
      } else if (key === "items") {
        const suffix = search ? "&query=" + encodeURIComponent(search) : "";
        const data = await jsonRequest<PageResponse<ListingRow>>("/api/backend/admin/listings?limit=50&offset=" + offset + suffix);
        setRecords(data.items); setTotal(data.total);
      } else if (key === "claims") {
        const data = await jsonRequest<PageResponse<ClaimRow>>("/api/backend/admin/claims?limit=50&offset=" + offset + "&query=" + encodeURIComponent(search));
        setRecords(data.items); setTotal(data.total);
      } else if (key === "matches") {
        const data = await jsonRequest<PageResponse<MatchRow>>("/api/backend/admin/matches?limit=50&offset=" + offset);
        setRecords(data.items); setTotal(data.total);
      } else if (key === "organizations") {
        const suffix = search ? "&query=" + encodeURIComponent(search) : "";
        const data = await jsonRequest<PageResponse<OrganizationRow>>("/api/backend/admin/organizations?limit=50&offset=" + offset + suffix);
        setRecords(data.items); setTotal(data.total);
      } else if (key === "users") {
        const suffix = search ? "&query=" + encodeURIComponent(search) : "";
        const data = await jsonRequest<PageResponse<UserRow>>("/api/backend/admin/users?limit=50&offset=" + offset + suffix);
        setRecords(data.items); setTotal(data.total);
      } else if (key === "moderation") {
        const data = await jsonRequest<ModerationRow[]>("/api/backend/admin/moderation/listings?limit=100");
        setRecords(data); setTotal(data.length);
      } else if (key === "support") {
        const data = await jsonRequest<PageResponse<TicketRow>>("/api/backend/admin/support/tickets?limit=50&offset=" + offset);
        setRecords(data.items); setTotal(data.total);
      } else if (key === "integrations") {
        const [healthResult, organizationsResult] = await Promise.all([
          jsonRequest<Health>("/api/backend/health/ready"),
          jsonRequest<PageResponse<OrganizationRow>>("/api/backend/admin/organizations?limit=100"),
        ]);
        setHealth(healthResult); setRecords(organizationsResult.items); setTotal(organizationsResult.total);
      } else if (key === "settings") {
        const data = await jsonRequest<SettingRow[]>("/api/backend/admin/settings");
        setRecords(data); setTotal(data.length);
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Не удалось загрузить данные");
    } finally {
      setLoading(false);
    }
  }, [loadSummary, offset]);

  useEffect(() => {
    const timer = window.setTimeout(() => { void loadSection(section, query); }, 220);
    return () => window.clearTimeout(timer);
  }, [section, query, loadSection]);

  useEffect(() => {
    function focusSearch(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchRef.current?.focus();
      }
    }
    window.addEventListener("keydown", focusSearch);
    return () => window.removeEventListener("keydown", focusSearch);
  }, []);

  function navigate(key: NavKey) {
    setSection(key); setOffset(0); setQuery(""); setMenuOpen(false); setSelected(null); setNotice("");
  }

  async function action(path: string, init: RequestInit, message: string) {
    setError("");
    try {
      await jsonRequest("/api/backend" + path, init);
      setNotice(message);
      await Promise.all([loadSection(section, query), loadSummary()]);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Действие не выполнено");
    }
  }

  const title = sectionTitles[section];
  const searchPlaceholder = useMemo(() => section === "organizations" ? "Название или ИНН…" : section === "users" ? "Имя пользователя…" : "ID, предмет, место…", [section]);
  const today = new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "long", year: "numeric", weekday: "long" }).format(new Date());

  return (
    <main className="admin-shell">
      <a className="skip-link" href="#admin-content">Перейти к содержимому</a>
      <aside className={"sidebar " + (menuOpen ? "open" : "")} aria-label="Главная навигация">
        <div className="brand"><span className="brand-mark">БН</span><div><strong>Бюро находок</strong><small>единая сеть</small></div><button className="mobile-close" aria-label="Закрыть меню" onClick={() => setMenuOpen(false)}>×</button></div>
        <div className="network-live"><i /><span><strong>Backend подключён</strong><small>данные обновляются по API</small></span></div>
        <nav>
          <small className="nav-label">УПРАВЛЕНИЕ</small>
          {navigation.slice(0, 8).map((item) => <button key={item.key} aria-current={section === item.key ? "page" : undefined} className={section === item.key ? "active" : ""} onClick={() => navigate(item.key)}><i aria-hidden="true">{item.icon}</i><span>{item.label}</span></button>)}
          <small className="nav-label second">СИСТЕМА</small>
          {navigation.slice(8).map((item) => <button key={item.key} aria-current={section === item.key ? "page" : undefined} className={section === item.key ? "active" : ""} onClick={() => navigate(item.key)}><i aria-hidden="true">{item.icon}</i><span>{item.label}</span></button>)}
        </nav>
        <div className="sidebar-foot"><button className="profile" onClick={onLogout}><span>{(user.display_name || "А").slice(0, 2).toUpperCase()}</span><span><strong>{user.display_name || "Администратор"}</strong><small>{user.role === "moderator" ? "Модератор · выйти" : "Главный администратор · выйти"}</small></span><i>↗</i></button></div>
      </aside>
      {menuOpen && <button className="mobile-scrim" aria-label="Закрыть меню" onClick={() => setMenuOpen(false)} />}
      <section className="workspace">
        <header className="topbar">
          <button className="mobile-menu" aria-label="Открыть меню" onClick={() => setMenuOpen(true)}>☰</button>
          <div className="global-search"><span aria-hidden="true">⌕</span><input ref={searchRef} aria-label="Поиск по текущему разделу" value={query} onChange={(event) => {setOffset(0); setQuery(event.target.value);}} placeholder={searchPlaceholder} /><kbd>⌘ K</kbd></div>
          <div className="top-actions"><button className="sync" onClick={() => void loadSection(section, query)}><i />Обновить данные</button><button className="notification" aria-label="Открытые обращения" onClick={() => navigate("support")}>◌<b>{analytics?.operations.support_open ?? 0}</b></button></div>
        </header>
        <div className="content" id="admin-content" role="main">
          <div className="page-head"><div><p>{today}</p><h1>{title.title}</h1><span>{title.subtitle}</span></div><div className="page-actions"><span className="period-button">Период: 30 дней</span><button className="primary-button" onClick={() => setAddOpen(true)}>＋ Добавить находку</button></div></div>
          {error && <div className="alert error-alert" role="alert"><strong>Ошибка</strong><span>{error}</span><button aria-label="Закрыть сообщение" onClick={() => setError("")}>×</button></div>}
          {notice && <div className="alert success-alert" role="status"><strong>Готово</strong><span>{notice}</span><button aria-label="Закрыть сообщение" onClick={() => setNotice("")}>×</button></div>}
          {loading && <div className="loading-line" role="status" aria-label="Загрузка данных"><i /></div>}
          {section === "overview" && <Dashboard analytics={analytics} dashboard={dashboard} audit={audit} onNavigate={navigate} />}
          {section === "items" && <Listings rows={records as ListingRow[]} total={total} onOpen={(row) => setSelected(row as unknown as Record<string, unknown>)} />}
          {section === "claims" && <Claims rows={records as ClaimRow[]} total={total} onAction={action} onOpen={(row) => setSelected(row as unknown as Record<string, unknown>)} />}
          {section === "matches" && <Matches rows={records as MatchRow[]} onAction={action} onOpen={(row) => setSelected(row as unknown as Record<string, unknown>)} />}
          {section === "organizations" && <Organizations rows={records as OrganizationRow[]} total={total} onAction={action} />}
          {section === "users" && <Users rows={records as UserRow[]} total={total} onAction={action} />}
          {section === "moderation" && <Moderation rows={records as ModerationRow[]} onAction={action} />}
          {section === "support" && <Support rows={records as TicketRow[]} total={total} onOpen={(row) => setSelected(row as unknown as Record<string, unknown>)} />}
          {section === "integrations" && <Integrations health={health} organizations={records as OrganizationRow[]} analytics={analytics} />}
          {section === "analytics" && <><TrafficCounts/><Analytics analytics={analytics} /></>}
          {["items","claims","matches","organizations","users","support"].includes(section) && <nav className="modal-actions" aria-label="Страницы реестра"><button className="filter-button" disabled={offset===0||loading} onClick={()=>setOffset(Math.max(0,offset-50))}>Назад</button><span>{offset+1}–{Math.min(offset+50,total)} из {number(total)}</span><button className="filter-button" disabled={offset+50>=total||loading} onClick={()=>setOffset(offset+50)}>Далее</button></nav>}
          {section === "settings" && <Settings rows={records as SettingRow[]} onAction={action} />}
        </div>
      </section>
      {selected && ["items", "claims", "support"].includes(section) ? <OperationalDrawer key={String(selected.id)} id={String(selected.id)} kind={section === "claims" ? "claim" : section === "support" ? "ticket" : "listing"} onClose={() => setSelected(null)} onChanged={() => {void loadSection(section,query); void loadSummary();}} /> : selected && <DetailDrawer data={selected} onClose={() => setSelected(null)} />}
      {addOpen && <AddModal onClose={() => setAddOpen(false)} onCreated={() => { setAddOpen(false); setNotice("Черновик создан. Откройте карточку в реестре, добавьте фотографии и отправьте её на модерацию."); void loadSection(section, query); void loadSummary(); }} />}
    </main>
  );
}

function Listings({ rows, total, onOpen }: { rows: ListingRow[]; total: number; onOpen: (row: ListingRow) => void }) {
  return <DataTable><div className="registry-tools"><div><strong>{number(total)}</strong><span> находок в реестре</span></div><a className="filter-button" href="/api/backend/admin/exports/overview.csv">⇩ Экспорт CSV</a></div><div className="data-table"><div className="data-row data-head"><span>ID</span><span>Предмет</span><span>Регион</span><span>Дата</span><span>Статус</span><span>Модерация</span><span /></div>{rows.map((row) => <button className="data-row" key={row.id} onClick={() => onOpen(row)}><code>{row.id.slice(0, 8)}</code><span className="item-cell"><i>{row.title.slice(0, 1)}</i><span><strong>{row.title}</strong><small>{row.category}</small></span></span><span>{row.region || "Не указан"}</span><span>{formatDate(row.created_at)}</span><Status tone={statusTone(row.status)}>{statusName(row.status)}</Status><Status tone={statusTone(row.moderation_status)}>{statusName(row.moderation_status)}</Status><span className="arrow">›</span></button>)}{!rows.length && <Empty />}</div></DataTable>;
}

function Claims({ rows, total, onOpen }: { rows: ClaimRow[]; total: number; onAction: (path: string, init: RequestInit, message: string) => void; onOpen: (row: ClaimRow) => void }) {
  return <section className="panel"><h2>Заявлений: {number(total)}</h2>{rows.map(row=><article className="ticket-row" key={row.id}><span><strong>Заявление {row.id.slice(0,8)}</strong><small>{formatDate(row.created_at)} · Риск {Math.round(row.risk_score*100)}%</small></span><Status>{statusName(row.status)}</Status><button className="primary-button" disabled={row.status === "draft"} onClick={()=>onOpen(row)}>Проверить доказательства</button></article>)}{!rows.length&&<Empty/>}</section>;
}

function Matches({ rows, onAction, onOpen }: { rows: MatchRow[]; onAction: (path: string, init: RequestInit, message: string) => void; onOpen: (row: MatchRow) => void }) {
  return <section className="matches-board">{rows.map((row) => <article className="match-card" key={row.id}><div className="match-top"><div><Status tone={row.score >= 80 ? "green" : "amber"}>{row.score >= 80 ? "Высокая вероятность" : "Требует проверки"}</Status><span>{formatDate(row.created_at)}</span></div><strong className="big-score">{row.score.toFixed(1)}%</strong></div><div className="comparison"><div className="compare-side"><span className="compare-image c1">П</span><div><small>ПОТЕРЯНО</small><h3>{row.source_listing_id.slice(0, 8)}</h3><p>Исходная карточка</p></div></div><div className="match-link"><i>✦</i><span>ИИ</span></div><div className="compare-side claim-side"><span className="compare-image c4">Н</span><div><small>НАЙДЕНО</small><h3>{row.candidate_listing_id.slice(0, 8)}</h3><p>Кандидат на совпадение</p></div></div></div><div className="match-reasons">{Object.entries(row.factors ?? {}).map(([key, value]) => <span key={key}>{key} <b>{Math.round(Math.min(100, Number(value) <= 1 ? Number(value) * 100 : Number(value)))}%</b></span>)}</div><div className="match-actions"><button className="filter-button" onClick={() => onOpen(row)}>Детали</button><div><button className="danger-button" disabled={row.status === "rejected"} onClick={() => void onAction("/listings/" + row.source_listing_id + "/matches/" + row.id, { method: "PATCH", body: JSON.stringify({ status: "rejected" }) }, "Совпадение отклонено")}>Отклонить</button><button className="primary-button" disabled={row.status === "accepted"} onClick={() => void onAction("/listings/" + row.source_listing_id + "/matches/" + row.id, { method: "PATCH", body: JSON.stringify({ status: "accepted" }) }, "Совпадение принято")}>Принять совпадение</button></div></div></article>)}{!rows.length && <section className="panel"><Empty /></section>}</section>;
}

function Organizations({ rows, total, onAction }: { rows: OrganizationRow[]; total: number; onAction: (path: string, init: RequestInit, message: string) => void }) {
  return <><section className="org-cards"><article><span>{number(total)}</span><strong>организаций</strong><small>в общей сети</small></article><article><span>{number(rows.reduce((sum, row) => sum + row.inventory, 0))}</span><strong>записей</strong><small>в текущей выборке</small></article><article><span>{rows.filter((row) => row.api_enabled).length}</span><strong>API включён</strong><small>организаций</small></article><article><span>{rows.reduce((sum, row) => sum + row.webhooks, 0)}</span><strong>вебхуков</strong><small>настроено</small></article></section><section className="panel registry-panel"><div className="org-table"><div className="org-row org-head"><span>Организация</span><span>ИНН</span><span>Находки</span><span>Вебхуки</span><span>API</span><span>Статус</span><span /></div>{rows.map((row) => <div className="org-row" key={row.id}><span className="org-name"><i>{row.name.slice(0, 1)}</i><strong>{row.name}</strong></span><span>{row.inn}</span><b>{row.inventory}</b><b>{row.webhooks}</b><b>{row.api_enabled ? "Вкл." : "Выкл."}</b><Status tone={statusTone(row.status)}>{statusName(row.status)}</Status>{row.status === "pending" ? <button className="primary-button mini-button" onClick={() => void onAction("/admin/organizations/" + row.id + "/verify", { method: "POST", body: JSON.stringify({ decision: "approve", reason: "Документы проверены администратором" }) }, "Организация подтверждена")}>Проверить</button> : <span />}</div>)}{!rows.length && <Empty />}</div></section></>;
}

function Users({ rows, total, onAction }: { rows: UserRow[]; total: number; onAction: (path: string, init: RequestInit, message: string) => void }) {
  return <section className="panel users-panel"><div className="user-stats"><div><strong>{number(total)}</strong><span>пользователей</span></div><div><strong>{rows.filter((row) => row.status === "active").length}</strong><span>активных в выборке</span></div><div><strong>{rows.filter((row) => row.admin_2fa_enabled).length}</strong><span>с включённой 2FA</span></div><div><strong>{rows.filter((row) => row.status === "blocked").length}</strong><span>ограничены</span></div></div><div className="user-grid">{rows.map((row) => <div className="user-card" key={row.id}><span className="avatar">{(row.display_name || "П").slice(0, 1)}</span><span><strong>{row.display_name || "Пользователь"}</strong><small>{row.phone_masked} · {row.role}</small></span><Status tone={statusTone(row.status)}>{statusName(row.status)}</Status><button className="filter-button mini-button" onClick={() => void onAction("/admin/users/" + row.id, { method: "PATCH", body: JSON.stringify({ status: row.status === "blocked" ? "active" : "blocked" }) }, row.status === "blocked" ? "Пользователь разблокирован" : "Пользователь заблокирован")}>{row.status === "blocked" ? "Разблокировать" : "Ограничить"}</button></div>)}</div>{!rows.length && <Empty />}</section>;
}

function Moderation({ rows, onAction }: { rows: ModerationRow[]; onAction: (path: string, init: RequestInit, message: string) => void }) {
  return <section className="moderation-layout"><div className="moderation-queue">{rows.map((row) => <article className="panel moderation-card" key={row.id}><div><MediaGallery media={row.media ?? []}/><p>{row.description}</p></div><div><Status tone="amber">Проверка</Status><h3>{row.title}</h3><p>{row.category} · {statusName(row.kind)}</p><small>{row.id.slice(0, 8)} · {formatDate(row.created_at)}</small></div><div><button className="filter-button" onClick={() => void onAction("/admin/moderation/listings/" + row.id, { method: "POST", body: JSON.stringify({ decision: "reject", reason: "Карточка не соответствует правилам публикации" }) }, "Карточка отклонена")}>Отклонить</button><button className="primary-button" onClick={() => void onAction("/admin/moderation/listings/" + row.id, { method: "POST", body: JSON.stringify({ decision: "approve", reason: "Карточка проверена администратором" }) }, "Карточка одобрена")}>Одобрить</button></div></article>)}{!rows.length && <section className="panel"><Empty text="Очередь модерации пуста" /></section>}</div><aside className="panel moderation-stats"><h2>Текущая очередь</h2><div><strong>{rows.length}</strong><span>ожидают решения</span></div><div><strong>API</strong><span>действия сохраняются</span></div><div><strong>Audit</strong><span>решения журналируются</span></div></aside></section>;
}

function Support({ rows, total, onOpen }: { rows: TicketRow[]; total: number; onOpen: (row: TicketRow) => void }) {
  return <section className="panel"><h2>Обращений: {number(total)}</h2>{rows.map(row=><article className="ticket-row" key={row.id}><span><strong>{row.subject}</strong><small>{formatDate(row.updated_at)}</small></span><Status>{statusName(row.status)}</Status><button className="primary-button" onClick={()=>onOpen(row)}>Читать и ответить</button></article>)}{!rows.length&&<Empty/>}</section>;
}

function Integrations({ health, organizations, analytics }: { health: Health | null; organizations: OrganizationRow[]; analytics: AnalyticsData | null }) {
  const cards = [
    ["FastAPI backend", health?.status ?? "checking", "Версия " + (health?.version ?? "—")],
    ["PostgreSQL", health?.database ?? "checking", "Основная база данных"],
    ["Redis", health?.redis ?? "checking", "Сессии, OTP и очередь"],
    ["API организаций", organizations.filter((row) => row.api_enabled).length + " активно", number(organizations.reduce((sum, row) => sum + row.inventory, 0)) + " записей"],
    ["Вебхуки", organizations.reduce((sum, row) => sum + row.webhooks, 0) + " настроено", (analytics?.operations.webhook_queue ?? 0) + " в очереди"],
    ["Ошибки доставок", String(analytics?.operations.webhook_failures ?? 0), "за текущий период"],
  ];
  return <section className="integration-grid">{cards.map((item, index) => <article className="panel integration-card" key={item[0]}><div className={"integration-icon int-" + (index + 1)}>{["↔", "▤", "◌", "◎", "➜", "!"][index]}</div><div><h3>{item[0]}</h3><p>{item[2]}</p></div><Status tone={String(item[1]).includes("ok") || String(item[1]).includes("ready") || String(item[1]).includes("актив") || item[1] === "0" ? "green" : "blue"}>{item[1]}</Status></article>)}</section>;
}

function Analytics({ analytics }: { analytics: AnalyticsData | null }) {
  const kpi = analytics?.kpi ?? {};
  const maxCategory = Math.max(...(analytics?.categories.map((item) => item.value) ?? [1]), 1);
  const maxRegion = Math.max(...(analytics?.regions.map((item) => item.value) ?? [1]), 1);
  return <><section className="analytics-top"><article className="panel hero-metric"><div><span>Возвращено за период</span><strong>{number(kpi.returned)}</strong><p><b>{(kpi.return_rate ?? 0).toFixed(1)}%</b> доля возврата</p></div><div className="ring-chart"><span>{Math.round(kpi.return_rate ?? 0)}%</span></div></article><article className="panel compact-metric"><span>Новые пользователи</span><strong>{number(kpi.new_users)}</strong><p>за выбранный период</p></article><article className="panel compact-metric"><span>Совпадения ИИ</span><strong>{number(kpi.matches)}</strong><p>{(kpi.claim_approval_rate ?? 0).toFixed(1)}% заявлений одобрено</p></article></section><section className="analytics-grid"><article className="panel categories"><div className="panel-head"><div><h2>Категории</h2><p>Распределение публикаций</p></div></div>{(analytics?.categories ?? []).map((item) => <div className="category-row" key={item.name ?? "other"}><span>{item.name ?? "Другое"}</span><div><i className="teal" style={{ width: ((item.value / maxCategory) * 100) + "%" }} /></div><b>{item.value}</b></div>)}{!analytics?.categories.length && <Empty />}</article><article className="panel geo-panel"><div className="panel-head"><div><h2>География</h2><p>Активность по регионам</p></div></div>{(analytics?.regions ?? []).map((item) => <div className="geo-row" key={item.name ?? "unknown"}><span>{item.name ?? "Не указан"}</span><div><i style={{ width: ((item.value / maxRegion) * 100) + "%" }} /></div><b>{item.value}</b></div>)}{!analytics?.regions.length && <Empty />}</article><article className="panel ai-quality"><div className="panel-head"><div><h2>Операционная сводка</h2><p>Очереди и сбои</p></div></div><div className="quality-grid"><div><b>{analytics?.operations.support_open ?? 0}</b><span>поддержка</span></div><div><b>{analytics?.operations.webhook_queue ?? 0}</b><span>вебхуки в очереди</span></div><div><b>{analytics?.operations.webhook_failures ?? 0}</b><span>ошибки вебхуков</span></div><div><b>{number(kpi.listings)}</b><span>публикаций</span></div></div></article></section></>;
}

function Settings({ rows, onAction }: { rows: SettingRow[]; onAction: (path: string, init: RequestInit, message: string) => void }) {
  return <section className="settings-grid">{rows.map((row, index) => <article className="panel setting-card" key={row.key}><div className="setting-icon">{["✦", "⌖", "◷", "⚙"][index % 4]}</div><div><h3>{row.key}</h3><p>{row.description || JSON.stringify(row.value)}</p></div><label className="switch"><input type="checkbox" checked={row.public} onChange={() => void onAction("/admin/settings/" + encodeURIComponent(row.key), { method: "PUT", body: JSON.stringify({ value: row.value, description: row.description, public: !row.public }) }, "Настройка обновлена")} /><i /></label></article>)}{!rows.length && <section className="panel"><Empty /></section>}</section>;
}

function DetailDrawer({ data, onClose }: { data: Record<string, unknown>; onClose: () => void }) {
  return <div className="overlay" onMouseDown={onClose}><aside className="drawer" role="dialog" aria-modal="true" aria-label="Детали записи" onMouseDown={(event) => event.stopPropagation()}><div className="drawer-head"><div><small>ДАННЫЕ ИЗ API</small><h2>{String(data.title ?? data.subject ?? data.name ?? data.id ?? "Карточка")}</h2></div><button aria-label="Закрыть карточку" onClick={onClose}>×</button></div><div className="drawer-section"><h3>Поля записи</h3><dl>{Object.entries(data).map(([key, value]) => <div key={key}><dt>{key}</dt><dd>{typeof value === "object" ? JSON.stringify(value) : String(value ?? "—")}</dd></div>)}</dl></div><div className="drawer-actions"><button className="primary-button" onClick={onClose}>Закрыть</button></div></aside></div>;
}

function AddModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ title: "", description: "", category: "personal", region: "Санкт-Петербург", address: "", storage: "" });
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError("");
    try {
      await jsonRequest("/api/backend/listings", { method: "POST", body: JSON.stringify({
        kind: "found", title: form.title, description: form.description, category: form.category,
        tags: [], public_features: [], hidden_features: [], event_at: new Date().toISOString(),
        location: { region: form.region, exact_address: form.address || null },
        media_ids: [], storage_code: form.storage || null, publish: false,
      }) });
      onCreated();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Не удалось создать находку");
    } finally { setBusy(false); }
  }
  return <div className="overlay modal-overlay" onMouseDown={onClose}><form className="modal" role="dialog" aria-modal="true" aria-label="Новая находка" onSubmit={submit} onMouseDown={(event) => event.stopPropagation()}><div className="drawer-head"><div><small>ПУБЛИКАЦИЯ</small><h2>Новая находка</h2></div><button type="button" aria-label="Закрыть форму" onClick={onClose}>×</button></div><div className="form-grid"><label><span>Название</span><input value={form.title} onChange={(event) => setForm({ ...form, title: event.target.value })} minLength={3} required /></label><label><span>Категория</span><select value={form.category} onChange={(event) => setForm({ ...form, category: event.target.value })}><option value="personal">Личные вещи</option><option value="electronics">Электроника</option><option value="documents">Документы</option><option value="bags">Сумки</option><option value="keys">Ключи</option></select></label><label className="wide"><span>Описание</span><textarea value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} minLength={10} required /></label><label><span>Регион</span><input value={form.region} onChange={(event) => setForm({ ...form, region: event.target.value })} required /></label><label><span>Точное место</span><input value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} /></label><label className="wide"><span>Код хранения</span><input value={form.storage} onChange={(event) => setForm({ ...form, storage: event.target.value })} placeholder="Например, A-104" /></label></div>{error && <div className="form-error">{error}</div>}<div className="modal-actions"><button type="button" className="filter-button" onClick={onClose}>Отмена</button><button className="primary-button" disabled={busy}>{busy ? "Создаём…" : "Сохранить черновик"}</button></div></form></div>;
}

function Empty({ text = "В базе пока нет записей" }: { text?: string }) {
  return <div className="empty-state"><span>⌕</span><strong>{text}</strong><p>Данные появятся здесь после операций в приложении.</p></div>;
}

export default function Home() {
  const [checking, setChecking] = useState(true);
  const [user, setUser] = useState<SessionUser | null>(null);
  useEffect(() => {
    jsonRequest<{ authenticated: boolean; user?: SessionUser }>("/api/session/status")
      .then((result) => setUser(result.user ?? null))
      .catch(() => setUser(null))
      .finally(() => setChecking(false));
  }, []);
  async function logout() {
    await fetch("/api/session/logout", { method: "POST" });
    setUser(null);
  }
  if (checking) return <main className="login-shell"><div className="boot-loader"><span className="brand-mark">БН</span><p>Загружаем кабинет…</p></div></main>;
  if (!user) return <Login onDone={setUser} />;
  return <AdminConsole user={user} onLogout={() => void logout()} />;
}
