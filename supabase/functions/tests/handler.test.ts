import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  createHandler,
  LabelClient,
  QueryResult,
} from "../label-pdf/handler.ts";

const fontBytes = await Deno.readFile(
  new URL("../label-pdf/assets/NotoSansJP-VariableFont_wght.ttf", import.meta.url),
);

const CONTAINER_ID = "e8000000-0000-4000-8000-000000000001";
const USER_ID = "e9000000-0000-4000-8000-000000000001";

const containerRow = {
  display_id: "選果-2027-001-1",
  original_weight_kg: 18.4,
  grade: { code: "M" },
  variety: { name: "ヘイワード" },
  sorting_result: {
    sorted_on: "2027-10-15",
    worker: { display_name: "大熊 太郎" },
    receiving_lot: { origin_name: "おおくま農園 第一圃場・A区画" },
  },
};

interface FakeConfig {
  user?: { id: string } | null;
  userError?: unknown;
  profile?: QueryResult<{ id: string }>;
  container?: QueryResult<unknown>;
}

// Minimal Supabase client fake: table results are pre-seeded and the chainable
// select/eq calls just return the same builder.
function fakeClient(config: FakeConfig): LabelClient {
  const results: Record<string, QueryResult<unknown>> = {
    profiles: config.profile ?? { data: { id: USER_ID }, error: null },
    containers: config.container ?? { data: containerRow, error: null },
  };
  return {
    auth: {
      getUser: (_token: string) =>
        Promise.resolve({
          data: { user: config.user === undefined ? { id: USER_ID } : config.user },
          error: config.userError ?? null,
        }),
    },
    from(table: string) {
      const query = {
        select: () => query,
        eq: () => query,
        maybeSingle: <T>() => Promise.resolve(results[table] as QueryResult<T>),
      };
      return query;
    },
  };
}

function handlerWith(config: FakeConfig) {
  return createHandler({ fontBytes, createClient: () => fakeClient(config) });
}

function getRequest(headers: Record<string, string> = { Authorization: "Bearer token" }) {
  return new Request(
    `http://localhost/label-pdf?container_id=${CONTAINER_ID}`,
    { method: "GET", headers },
  );
}

Deno.test("returns a PDF with exposed headers on success", async () => {
  const res = await handlerWith({})(getRequest());
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Type"), "application/pdf");
  const exposed = res.headers.get("Access-Control-Expose-Headers") ?? "";
  assert(exposed.includes("X-Label-Layout-Version"), "layout version must be exposed");
  assert(exposed.includes("Content-Disposition"), "content disposition must be exposed");
  assertEquals(res.headers.get("X-Label-Layout-Version"), "1");
  const body = new Uint8Array(await res.arrayBuffer());
  assert(body.length > 0, "a non-empty PDF is returned");
  assertEquals(String.fromCharCode(...body.subarray(0, 5)), "%PDF-");
});

Deno.test("preflight exposes headers for the browser", async () => {
  const res = await handlerWith({})(
    new Request("http://localhost/label-pdf", { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
  const exposed = res.headers.get("Access-Control-Expose-Headers") ?? "";
  assert(exposed.includes("X-Label-Layout-Version"));
  assert(exposed.includes("Content-Disposition"));
  await res.body?.cancel();
});

Deno.test("a profile lookup failure is a retryable UNEXPECTED, not a 403", async () => {
  const res = await handlerWith({
    profile: { data: null, error: { message: "connection reset" } },
  })(getRequest());
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error.code, "UNEXPECTED");
});

Deno.test("a missing profile is a permission decision (403)", async () => {
  const res = await handlerWith({ profile: { data: null, error: null } })(getRequest());
  assertEquals(res.status, 403);
  const body = await res.json();
  assertEquals(body.error.code, "AUTH_FORBIDDEN");
});

Deno.test("a container query failure is UNEXPECTED", async () => {
  const res = await handlerWith({
    container: { data: null, error: { message: "statement timeout" } },
  })(getRequest());
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error.code, "UNEXPECTED");
});

Deno.test("an unknown container is 404", async () => {
  const res = await handlerWith({ container: { data: null, error: null } })(getRequest());
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.error.code, "CONTAINER_NOT_FOUND");
});

Deno.test("a missing session is 401", async () => {
  const res = await handlerWith({ user: null })(getRequest());
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "AUTH_REQUIRED");
});

Deno.test("a missing bearer token is 401 before any client call", async () => {
  const res = await handlerWith({})(getRequest({}));
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error.code, "AUTH_REQUIRED");
});

Deno.test("a malformed container id is 400", async () => {
  const res = await handlerWith({})(
    new Request("http://localhost/label-pdf?container_id=not-a-uuid", {
      method: "GET",
      headers: { Authorization: "Bearer token" },
    }),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.code, "VALIDATION_FAILED");
});
