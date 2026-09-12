import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  CalendarTask,
  eventBody,
  googleCalendar,
  SyncError,
  tokenProvider,
} from "../calendar-sync/google.ts";
import { createHandler, Job } from "../calendar-sync/handler.ts";

const task: CalendarTask = {
  id: "57000000-0000-4000-8000-000000000001",
  task_type: "ethylene_injection",
  status: "pending",
  scheduled_at: "2027-05-10T00:00:00Z",
  due_at: "2027-05-10T00:00:00Z",
  target_url: "/work-tasks/57000000-0000-4000-8000-000000000001",
  version: 1,
  calendar_event_id: "task57000000000040008000000000000001g0",
  task_details: {
    variety: "ヘイワード",
    grade: "L",
    weight_kg: 6,
    location: "追熟室",
  },
};
const job: Job = { task, revision: 1, lease_token: "lease" };
Deno.test("calendar event contains only the allowed business fields", () => {
  const body = eventBody({
    ...task,
    task_details: {
      ...task.task_details,
      customer_name: "PRIVATE",
      address: "SECRET",
      notes: "HIDDEN",
    } as CalendarTask["task_details"],
  }, "https://farm.example");
  assert(body.summary.includes("エチレン注入"));
  assert(body.description.includes("https://farm.example/work-tasks/"));
  assert(!JSON.stringify(body).includes("PRIVATE"));
  assert(!JSON.stringify(body).includes("SECRET"));
  assert(!JSON.stringify(body).includes("HIDDEN"));
  assertEquals(body.end.dateTime, "2027-05-10T00:15:00.000Z");
});
Deno.test("cancelled event is retained with a visible cancellation marker", () => {
  const body = eventBody(
    { ...task, status: "cancelled" },
    "https://farm.example",
  );
  assert(body.summary.startsWith("【中止】"));
  assertEquals(body.status, "confirmed");
  assertEquals(body.transparency, "transparent");
});
Deno.test("shipping is an all-day event in the persisted local shipping date", () => {
  const body = eventBody({
    ...task,
    task_type: "shipping",
    task_details: { ...task.task_details, shipping_date: "2027-05-10" },
  }, "https://farm.example");
  assertEquals(body.start, { date: "2027-05-10" });
  assertEquals(body.end, { date: "2027-05-11" });
});
Deno.test("calendar descriptions escape master names and cannot change the link host", async () => {
  const body = eventBody({
    ...task,
    task_details: { ...task.task_details, variety: "<script>" },
  }, "https://farm.example");
  assert(body.description.includes("&lt;script&gt;"));
  await assertRejects(
    async () =>
      eventBody(
        { ...task, target_url: "//other.example" },
        "https://farm.example",
      ),
    SyncError,
    "TASK_INVALID",
  );
});
Deno.test("existing event is fully overwritten on every sync, including unchanged task versions", async () => {
  const calls: { method: string; body: unknown }[] = [];
  const sync = googleCalendar(
    "farm@group.calendar.google.com",
    "https://farm.example",
    () => Promise.resolve("token"),
    (_url, init) => {
      calls.push({
        method: init!.method!,
        body: JSON.parse(init!.body as string),
      });
      return Promise.resolve(new Response("{}"));
    },
  );
  await sync(task);
  await sync(task);
  assertEquals(calls.length, 2);
  assertEquals(calls[0].method, "PUT");
  assertEquals(calls[0].body, calls[1].body);
});
Deno.test("missing event inserts a deterministic ID and retries the same ID after a lost response", async () => {
  const ids: string[] = [];
  let calls = 0;
  const sync = googleCalendar(
    "farm",
    "https://farm.example",
    () => Promise.resolve("token"),
    (_url, init) => {
      calls++;
      if (init!.method === "PUT") {
        return Promise.resolve(
          new Response("", { status: 404 }),
        );
      }
      ids.push(JSON.parse(init!.body as string).id);
      if (calls === 2) throw new Error("network lost after insert");
      return Promise.resolve(new Response("{}"));
    },
  );
  await assertRejects(() => sync(task), SyncError, "GOOGLE_UNAVAILABLE");
  await sync(task);
  assertEquals(ids, [task.calendar_event_id, task.calendar_event_id]);
});
Deno.test("insert conflict is repaired with a full update", async () => {
  const statuses = [404, 409, 200], methods: string[] = [];
  const sync = googleCalendar(
    "farm",
    "https://farm.example",
    () => Promise.resolve("token"),
    (_url, init) => {
      methods.push(init!.method!);
      return Promise.resolve(new Response("{}", { status: statuses.shift()! }));
    },
  );
  await sync(task);
  assertEquals(methods, ["PUT", "POST", "PUT"]);
});
for (
  const [status, code] of [
    [429, "GOOGLE_RATE_LIMIT"],
    [403, "GOOGLE_ACCESS_DENIED"],
    [500, "GOOGLE_UNAVAILABLE"],
    [410, "GOOGLE_EVENT_GONE"],
  ] as const
) {
  Deno.test(
    "Google " + status + " produces a sanitized retry code",
    async () => {
      const sync = googleCalendar(
        "farm",
        "https://farm.example",
        () => Promise.resolve("token"),
        () =>
          Promise.resolve(
            new Response("sensitive provider message", { status }),
          ),
      );
      await assertRejects(
        () => sync(task),
        SyncError,
        code,
      );
    },
  );
}
Deno.test("worker denies anonymous requests and wrong methods without claiming jobs", async () => {
  let claimed = 0;
  const handler = createHandler({
    secret: "scheduler-token",
    store: {
      claim: () => {
        claimed++;
        return Promise.resolve([]);
      },
      finish: () => Promise.resolve(true),
    },
    sync: () => Promise.resolve(),
  });
  assertEquals(
    (await handler(new Request("https://edge.example", { method: "POST" })))
      .status,
    401,
  );
  assertEquals(
    (await handler(new Request("https://edge.example"))).status,
    405,
  );
  assertEquals(claimed, 0);
});
Deno.test("worker records one failure without dropping other jobs and reports stale acknowledgements", async () => {
  const finished: (string | null)[] = [];
  const jobs = [job, { ...job, task: { ...task, id: "two" } }, {
    ...job,
    task: { ...task, id: "three" },
  }];
  const handler = createHandler({
    secret: "scheduler-token",
    store: {
      claim: () => Promise.resolve(jobs),
      finish: (j, code) => {
        finished.push(code);
        return Promise.resolve(j.task.id !== "three");
      },
    },
    sync: (t) =>
      t.id === "two"
        ? Promise.reject(new SyncError("GOOGLE_RATE_LIMIT"))
        : Promise.resolve(),
  });
  const response = await handler(
    new Request("https://edge.example", {
      method: "POST",
      headers: { "x-calendar-sync-token": "scheduler-token" },
    }),
  );
  assertEquals(await response.json(), {
    claimed: 3,
    synced: 1,
    failed: 1,
    stale: 1,
  });
  assert(finished.includes("GOOGLE_RATE_LIMIT"));
});
Deno.test("DB failure returns a sanitized error and leases remain available for recovery", async () => {
  const handler = createHandler({
    secret: "scheduler-token",
    store: {
      claim: () => Promise.reject(new Error("secret connection")),
      finish: () => Promise.resolve(true),
    },
    sync: () => Promise.resolve(),
  });
  const response = await handler(
    new Request("https://edge.example", {
      method: "POST",
      headers: { "x-calendar-sync-token": "scheduler-token" },
    }),
  );
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "SYNC_WORKER_UNAVAILABLE" });
});
Deno.test("service-account OAuth assertion is signed, scoped, and cached", async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const keyBytes = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const pem = "-----BEGIN PRIVATE KEY-----\n" +
    btoa(String.fromCharCode(...keyBytes)) + "\n-----END PRIVATE KEY-----";
  let calls = 0;
  const provider = tokenProvider({
    client_email: "calendar@example.iam.gserviceaccount.com",
    private_key: pem,
  }, async (url, init) => {
    calls++;
    assertEquals(url, "https://oauth2.googleapis.com/token");
    const assertion = (init!.body as URLSearchParams).get("assertion")!;
    const [header, payload, signature] = assertion.split(".");
    const decode = (s: string) =>
      Uint8Array.from(
        atob(s.replace(/-/g, "+").replace(/_/g, "/")),
        (c) => c.charCodeAt(0),
      );
    assert(
      await crypto.subtle.verify(
        "RSASSA-PKCS1-v1_5",
        pair.publicKey,
        decode(signature),
        new TextEncoder().encode(header + "." + payload),
      ),
    );
    const claims = JSON.parse(new TextDecoder().decode(decode(payload)));
    assertEquals(
      claims.scope,
      "https://www.googleapis.com/auth/calendar.events",
    );
    assertEquals(claims.exp - claims.iat, 3600);
    assertEquals(claims.sub, undefined);
    return new Response(
      JSON.stringify({ access_token: "access", expires_in: 3600 }),
    );
  });
  assertEquals(await provider(), "access");
  assertEquals(await provider(), "access");
  assertEquals(calls, 1);
});

Deno.test("an acknowledgement failure waits for other in-flight jobs before returning 503", async () => {
  let otherFinished = false;
  const handler = createHandler({
    secret: "scheduler-token",
    store: {
      claim: () =>
        Promise.resolve([job, { ...job, task: { ...task, id: "other" } }]),
      finish: async (current) => {
        if (current.task.id === task.id) throw new Error("database lost");
        await new Promise((resolve) => setTimeout(resolve, 10));
        otherFinished = true;
        return true;
      },
    },
    sync: () => Promise.resolve(),
  });
  const response = await handler(
    new Request("https://edge.example", {
      method: "POST",
      headers: { "x-calendar-sync-token": "scheduler-token" },
    }),
  );
  assertEquals(response.status, 503);
  assert(otherFinished);
});
Deno.test("a missing calendar is an access warning, not an event-ID rotation", async () => {
  const sync = googleCalendar(
    "missing-calendar",
    "https://farm.example",
    () => Promise.resolve("token"),
    () => Promise.resolve(new Response("", { status: 404 })),
  );
  await assertRejects(() => sync(task), SyncError, "GOOGLE_ACCESS_DENIED");
});
