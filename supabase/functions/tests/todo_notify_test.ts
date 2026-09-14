import {
  createHandler,
  Dependencies,
  japanDay,
  message,
  webhookUrl,
} from "../todo-notify/handler.ts";
function assert(value: unknown) {
  if (!value) throw Error("Assertion failed");
}
const now = new Date("2026-09-14T23:00:00Z");
function setup(overrides: Partial<Dependencies> = {}) {
  let sends = 0;
  let begins = 0;
  const finishes: string[] = [];
  const deps: Dependencies = {
    authenticate: () => Promise.resolve("admin"),
    configured: () => true,
    begin: () => {
      begins++;
      return Promise.resolve({ claimed: true, id: "job" });
    },
    tasks: () => Promise.resolve({ rows: [], count: 0 }),
    send: () => {
      sends++;
      return Promise.resolve(true);
    },
    finish: (_id, status) => {
      finishes.push(status);
      return Promise.resolve();
    },
    now: () => now,
    ...overrides,
  };
  return {
    handle: createHandler(deps),
    get sends() {
      return sends;
    },
    get begins() {
      return begins;
    },
    finishes,
  };
}
function request(mode = "manual") {
  return new Request("https://example.test", {
    method: "POST",
    body: JSON.stringify({
      mode,
      request_id: "11111111-1111-4111-8111-111111111111",
    }),
  });
}
Deno.test("Japan day starts at previous UTC 15:00", () => {
  const day = japanDay(now);
  assert(day.date === "2026-09-15");
  assert(day.start === "2026-09-14T15:00:00.000Z");
  assert(day.end === "2026-09-15T15:00:00.000Z");
  assert(japanDay(new Date("2026-09-14T14:59:59Z")).date === "2026-09-14");
});
Deno.test("Webhook validates destination and waits for delivery", () => {
  assert(
    webhookUrl("https://discord.com/api/webhooks/123/test").search ===
      "?wait=true",
  );
  for (
    const value of [
      "http://discord.com/api/webhooks/123/test",
      "https://evil.test/api/webhooks/123/test",
      "https://discord.com/api/webhooks/123/test?wait=false",
    ]
  ) {
    let rejected = false;
    try {
      webhookUrl(value);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("Message disables mentions, limits length and describes omitted tasks", () => {
  const task = {
    id: "11111111-1111-4111-8111-111111111111",
    task_type: "shipping",
    scheduled_at: now.toISOString(),
  };
  const data = message(
    "2026-09-15",
    Array(10).fill(task),
    200,
    "https://" + "a".repeat(180) + ".test",
  );
  assert(data.content.length <= 2000);
  assert(data.allowed_mentions.parse.length === 0);
  assert(data.content.includes("全件はホーム"));
  assert(
    message("2026-09-15", [], 0, "https://example.test").content.includes(
      "ありません",
    ),
  );
});
Deno.test("Unauthorized calls do not enqueue or send", async () => {
  const test = setup({ authenticate: () => Promise.reject(Error()) });
  assert((await test.handle(request())).status === 403);
  assert(test.begins === 0);
  assert(test.sends === 0);
});
Deno.test("Missing config does not claim a request", async () => {
  const test = setup({ configured: () => false });
  assert((await test.handle(request())).status === 503);
  assert(test.begins === 0);
});
Deno.test("Successful notification records sent only after provider success", async () => {
  const test = setup();
  assert((await test.handle(request())).status === 200);
  assert(test.sends === 1);
  assert(test.finishes[0] === "sent");
});
Deno.test("Replayed or rate limited request never sends again", async () => {
  for (const status of ["sent", "sending", "rate_limited"]) {
    const test = setup({
      begin: () => Promise.resolve({ claimed: false, status }),
    });
    await test.handle(request());
    assert(test.sends === 0);
  }
});
Deno.test("Ambiguous provider failure records unknown rather than claiming success", async () => {
  const test = setup({
    send: () => Promise.reject(Error("secret provider response")),
  });
  const response = await test.handle(request());
  assert(response.status === 503);
  assert(test.finishes[0] === "unknown");
  assert(!(await response.text()).includes("secret provider"));
});
Deno.test("Provider rejection records failure", async () => {
  const test = setup({ send: () => Promise.resolve(false) });
  assert((await test.handle(request())).status === 502);
  assert(test.finishes[0] === "failed");
});
Deno.test("Daily uses the Japanese day as idempotency key", async () => {
  let key = "";
  const test = setup({
    authenticate: () => Promise.resolve(null),
    begin: (value) => {
      key = value;
      return Promise.resolve({ claimed: true, id: "job" });
    },
  });
  await test.handle(request("daily"));
  assert(key === "daily:2026-09-15");
});
