export type Task = { id: string; task_type: string; scheduled_at: string };
export function japanDay(now: Date) {
  const date = new Date(now.getTime() + 9 * 3600000).toISOString().slice(0, 10);
  const start = new Date(date + "T00:00:00+09:00");
  return {
    date,
    start: start.toISOString(),
    end: new Date(start.getTime() + 86400000).toISOString(),
  };
}
export function webhookUrl(value: string): URL {
  const url = new URL(value);
  if (
    url.protocol !== "https:" || url.hostname !== "discord.com" || url.port ||
    url.username || url.password ||
    !/^\/api(?:\/v[0-9]+)?\/webhooks\/[0-9]+\/[A-Za-z0-9_-]+$/.test(
      url.pathname,
    ) || url.hash || url.search
  ) throw Error("CONFIG_MISSING");
  url.searchParams.set("wait", "true");
  return url;
}
export function message(
  date: string,
  tasks: Task[],
  count: number,
  base: string,
) {
  const labels: Record<string, string> = {
    sorting: "選果登録",
    label: "ラベル対応",
    ethylene_injection: "エチレン注入",
    ethylene_removal_check: "エチレン抜き確認",
    ripeness_check: "追熟確認",
    shipping: "出荷確認",
  };
  const url = new URL(base);
  if (
    url.protocol !== "https:" || url.username || url.password || url.search ||
    url.hash || url.pathname !== "/" || url.origin.length > 200
  ) throw Error("CONFIG_MISSING");
  const lines = [
    `おおくま農園｜${date} 本日のToDo（日本時間）`,
    `未完了 ${count}件`,
  ];
  let shown = 0;
  for (const task of tasks.slice(0, 10)) {
    if (!/^[0-9a-f-]{36}$/.test(task.id)) throw Error("DATA_UNAVAILABLE");
    const time = new Date(new Date(task.scheduled_at).getTime() + 9 * 3600000)
      .toISOString().slice(11, 16);
    const line = `${time} ${
      labels[task.task_type] ?? "作業確認"
    }\n<${url.origin}/work-tasks/${task.id}>`;
    if (
      lines.join("\n").length + line.length + url.origin.length + 100 > 2000
    ) break;
    lines.push(line);
    shown++;
  }
  if (count === 0) lines.push("本日の未完了ToDoはありません。");
  if (count > shown) {
    lines.push(`ほか${count - shown}件。全件はホームで確認してください。`);
  }
  lines.push(`<${url.origin}>`);
  return {
    content: lines.join("\n"),
    allowed_mentions: { parse: [] },
    flags: 4,
  };
}
export interface Dependencies {
  authenticate(request: Request, mode: string): Promise<string | null>;
  configured(): boolean;
  begin(
    key: string,
    mode: string,
    actor: string | null,
  ): Promise<{ claimed: boolean; id?: string; status?: string }>;
  tasks(start: string, end: string): Promise<{ rows: Task[]; count: number }>;
  send(date: string, rows: Task[], count: number): Promise<boolean>;
  finish(
    id: string,
    status: string,
    count: number | null,
    error: string | null,
  ): Promise<void>;
  now(): Date;
}
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const reply = (status: number, data: unknown) =>
      Response.json(data, { status, headers: cors });
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (req.method !== "POST") {
      return reply(405, { error: "METHOD_NOT_ALLOWED" });
    }
    let body;
    try {
      body = await req.json();
    } catch {
      return reply(400, { error: "INVALID_REQUEST" });
    }
    if (!body || !["manual", "daily"].includes(body.mode)) {
      return reply(400, { error: "INVALID_REQUEST" });
    }
    let actor;
    try {
      actor = await deps.authenticate(req, body.mode);
    } catch {
      return reply(403, { error: "AUTH_FORBIDDEN" });
    }
    if (!deps.configured()) return reply(503, { error: "CONFIG_MISSING" });
    const day = japanDay(deps.now());
    if (
      body.mode === "manual" &&
      (typeof body.request_id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
          .test(body.request_id))
    ) return reply(400, { error: "INVALID_REQUEST" });
    const key = body.mode === "daily"
      ? `daily:${day.date}`
      : `manual:${actor}:${body.request_id}`;
    let id: string | undefined;
    let count: number | null = null;
    let status = "failed";
    let error: string | null = "DATA_UNAVAILABLE";
    try {
      const claim = await deps.begin(key, body.mode, actor);
      if (!claim.claimed) {
        return reply(claim.status === "rate_limited" ? 429 : 200, {
          status: claim.status,
          replayed: true,
        });
      }
      id = claim.id;
      if (!id) throw Error();
      const data = await deps.tasks(day.start, day.end);
      count = data.count;
      status = "unknown";
      error = "DELIVERY_UNKNOWN";
      if (await deps.send(day.date, data.rows, data.count)) {
        status = "sent";
        error = null;
      } else {
        status = "failed";
        error = "DISCORD_REJECTED";
      }
      await deps.finish(id, status, count, error);
      return reply(status === "sent" ? 200 : 502, { status, count, error });
    } catch {
      if (id) {
        try {
          await deps.finish(id, status, count, error);
        } catch { /* do not log credentials */ }
      }
      return reply(503, { status, error });
    }
  };
}
