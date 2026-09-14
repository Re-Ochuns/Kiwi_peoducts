import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { createHandler, message, webhookUrl } from "./handler.ts";
const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: AbortSignal.timeout(10000) }),
    },
  },
);
const webhook = Deno.env.get("DISCORD_TODO_WEBHOOK_URL") ?? "";
const base = Deno.env.get("APP_BASE_URL") ?? "";
Deno.serve(createHandler({
  now: () => new Date(),
  async authenticate(req, mode) {
    if (mode === "daily") {
      const expected = Deno.env.get("TODO_NOTIFICATION_TOKEN");
      const actual = req.headers.get("x-todo-notification-token");
      if (!expected || !actual) throw Error();
      const hash = (v: string) =>
        crypto.subtle.digest("SHA-256", new TextEncoder().encode(v));
      const [a, b] = await Promise.all([hash(actual), hash(expected)]);
      if (
        new Uint8Array(a).reduce(
          (n, v, i) => n | (v ^ new Uint8Array(b)[i]),
          0,
        ) !== 0
      ) throw Error();
      return null;
    }
    const token = req.headers.get("Authorization")?.match(/^Bearer (.+)$/i)
      ?.[1];
    if (!token) throw Error();
    const { data, error } = await client.auth.getUser(token);
    if (error || !data.user) throw Error();
    const [profile, roles] = await Promise.all([
      client.from("profiles").select("access_status").eq("id", data.user.id)
        .single(),
      client.from("user_roles").select("role").eq("user_id", data.user.id).eq(
        "role",
        "administrator",
      ),
    ]);
    if (
      profile.error || roles.error ||
      profile.data?.access_status !== "active" || !roles.data?.length
    ) throw Error();
    return data.user.id;
  },
  configured() {
    try {
      webhookUrl(webhook);
      message("2000-01-01", [], 0, base);
      return true;
    } catch {
      return false;
    }
  },
  async begin(key, mode, actor) {
    const { data, error } = await client.rpc("todo_notification_begin", {
      key_value: key,
      mode_value: mode,
      actor_value: actor,
    });
    if (error) throw Error();
    return data;
  },
  async tasks(start, end) {
    const { data, count, error } = await client.from("work_tasks").select(
      "id,task_type,scheduled_at",
      { count: "exact" },
    ).eq("status", "pending").gte("scheduled_at", start).lt("scheduled_at", end)
      .order("scheduled_at").order("id").limit(10);
    if (error || count === null) throw Error();
    return { rows: data, count };
  },
  async send(date, rows, count) {
    const response = await fetch(webhookUrl(webhook), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(message(date, rows, count, base)),
      signal: AbortSignal.timeout(15000),
      redirect: "error",
    });
    return response.ok;
  },
  async finish(id, status, count, error) {
    const { error: failure } = await client.rpc("todo_notification_finish", {
      id_value: id,
      status_value: status,
      count_value: count,
      error_value: error,
    });
    if (failure) throw Error();
  },
}));
