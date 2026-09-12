export type Fetcher = (url: string, init: {
  method: string;
  signal: AbortSignal;
  headers: Record<string, string>;
  body: string | URLSearchParams;
}) => Promise<Response>;
export interface CalendarTask {
  id: string;
  task_type: string;
  status: string;
  scheduled_at: string;
  due_at: string;
  target_url: string;
  version: number;
  calendar_event_id: string;
  task_details: {
    variety: string;
    grade: string;
    weight_kg: number;
    location?: string;
    shipping_date?: string;
  };
}
export class SyncError extends Error {
  constructor(public code: string) {
    super(code);
  }
}
const labels: Record<string, string> = {
  ethylene_injection: "エチレン注入",
  ethylene_removal_check: "エチレン抜き確認",
  ripeness_check: "追熟確認",
  shipping: "出荷",
};
const escapeHtml = (s: string) =>
  s.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
export function eventBody(task: CalendarTask, appBaseUrl: string) {
  const base = new URL(appBaseUrl);
  if (
    base.protocol !== "https:" || base.search || base.hash || base.username ||
    base.password
  ) {
    throw new SyncError("CONFIG_INVALID");
  }
  if (!/^\/work-tasks\/[0-9a-f-]{36}$/.test(task.target_url)) {
    throw new SyncError("TASK_INVALID");
  }
  const label = labels[task.task_type];
  if (!label) throw new SyncError("TASK_INVALID");
  const d = task.task_details;
  const marker = task.status === "cancelled"
    ? "【中止】"
    : task.status === "completed"
    ? "【完了】"
    : "";
  const url = base.toString().replace(/\/$/, "") + task.target_url;
  const start = new Date(task.scheduled_at);
  const due = new Date(task.due_at);
  if (
    !Number.isFinite(start.getTime()) || !Number.isFinite(due.getTime()) ||
    due < start
  ) throw new SyncError("TASK_INVALID");
  const body = {
    summary: `${marker}${label} / ${d.variety} / ${d.grade} / ${d.weight_kg}kg`,
    description: [
      label,
      d.variety,
      d.grade,
      `${d.weight_kg}kg`,
      d.location ?? "",
      url,
    ].map(escapeHtml).join("\n"),
    location: d.location ?? "",
    status: "confirmed",
    transparency: task.status === "cancelled" ? "transparent" : "opaque",
    attendees: [],
    reminders: { useDefault: false },
    recurrence: [],
    extendedProperties: {
      private: { kiwi_task_id: task.id, kiwi_version: String(task.version) },
    },
    start: {} as Record<string, string>,
    end: {} as Record<string, string>,
  };
  if (task.task_type === "shipping") {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d.shipping_date ?? "")) {
      throw new SyncError("TASK_INVALID");
    }
    body.start = { date: d.shipping_date! };
    body.end = {
      date: new Date(Date.parse(d.shipping_date! + "T00:00:00Z") + 86400000)
        .toISOString().slice(0, 10),
    };
  } else {
    body.start = { dateTime: start.toISOString(), timeZone: "Asia/Tokyo" };
    // A 15-minute display slot is not a processing-duration calculation.
    body.end = {
      dateTime: new Date(Math.max(due.getTime(), start.getTime() + 900000))
        .toISOString(),
      timeZone: "Asia/Tokyo",
    };
  }
  return body;
}
function base64url(value: Uint8Array): string {
  return btoa(String.fromCharCode(...value)).replace(/=/g, "").replace(
    /\+/g,
    "-",
  ).replace(/\//g, "_");
}
export interface ServiceAccount {
  client_email: string;
  private_key: string;
}
export function tokenProvider(
  account: ServiceAccount,
  request: Fetcher = fetch,
  now = () => Date.now(),
) {
  let cached: { token: string; until: number } | undefined;
  return async (): Promise<string> => {
    if (cached && now() < cached.until) return cached.token;
    if (!account.client_email || !account.private_key) {
      throw new SyncError("CONFIG_MISSING");
    }
    try {
      const encode = (x: unknown) =>
        base64url(new TextEncoder().encode(JSON.stringify(x)));
      const issued = Math.floor(now() / 1000);
      const unsigned = encode({ alg: "RS256", typ: "JWT" }) + "." + encode({
        iss: account.client_email,
        scope: "https://www.googleapis.com/auth/calendar.events",
        aud: "https://oauth2.googleapis.com/token",
        iat: issued,
        exp: issued + 3600,
      });
      const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(
        /\s/g,
        "",
      );
      const key = await crypto.subtle.importKey(
        "pkcs8",
        Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const signature = await crypto.subtle.sign(
        "RSASSA-PKCS1-v1_5",
        key,
        new TextEncoder().encode(unsigned),
      );
      const response = await request("https://oauth2.googleapis.com/token", {
        method: "POST",
        signal: AbortSignal.timeout(10000),
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion: unsigned + "." + base64url(new Uint8Array(signature)),
        }),
      });
      if (!response.ok) throw new SyncError("GOOGLE_AUTH_FAILED");
      const result = await response.json();
      if (
        typeof result.access_token !== "string" ||
        !Number.isFinite(result.expires_in) || result.expires_in <= 60
      ) throw new SyncError("GOOGLE_AUTH_FAILED");
      cached = {
        token: result.access_token,
        until: now() + (result.expires_in - 60) * 1000,
      };
      return cached.token;
    } catch (error) {
      if (error instanceof SyncError) throw error;
      throw new SyncError("GOOGLE_AUTH_FAILED");
    }
  };
}
export function googleCalendar(
  calendarId: string,
  appBaseUrl: string,
  getToken: () => Promise<string>,
  request: Fetcher = fetch,
) {
  return async (task: CalendarTask): Promise<void> => {
    if (!calendarId || !/^[a-v0-9]{5,1024}$/.test(task.calendar_event_id)) {
      throw new SyncError("CONFIG_INVALID");
    }
    const token = await getToken();
    const root = "https://www.googleapis.com/calendar/v3/calendars/" +
      encodeURIComponent(calendarId) + "/events";
    const body = eventBody(task, appBaseUrl);
    const call = (method: string, url: string, payload: unknown) =>
      request(url + "?sendUpdates=none", {
        method,
        signal: AbortSignal.timeout(10000),
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
    try {
      let conflicted = false;
      let response = await call(
        "PUT",
        root + "/" + task.calendar_event_id,
        body,
      );
      if (response.status === 404) {
        response = await call("POST", root, {
          ...body,
          id: task.calendar_event_id,
        });
        if (response.status === 409) {
          conflicted = true;
          response = await call(
            "PUT",
            root + "/" + task.calendar_event_id,
            body,
          );
        }
      }
      if (response.status === 410 || (response.status === 404 && conflicted)) {
        throw new SyncError("GOOGLE_EVENT_GONE");
      }
      if (!response.ok) {
        throw new SyncError(
          response.status === 429
            ? "GOOGLE_RATE_LIMIT"
            : response.status === 401 || response.status === 403 ||
                response.status === 404
            ? "GOOGLE_ACCESS_DENIED"
            : "GOOGLE_UNAVAILABLE",
        );
      }
    } catch (error) {
      if (error instanceof SyncError) throw error;
      throw new SyncError("GOOGLE_UNAVAILABLE");
    }
  };
}
