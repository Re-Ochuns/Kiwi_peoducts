import { assert, assertEquals } from "jsr:@std/assert@1";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import {
  createHandler,
  LabelClient,
  QueryResult,
  RipeningLabelRow,
  SortingLabelBatchRow,
} from "../label-pdf/handler.ts";

const sortingFontBytes = await Deno.readFile(
  new URL(
    "../label-pdf/assets/NotoSansJP-SemiBold.ttf",
    import.meta.url,
  ),
);
const ripeningFontBytes = await Deno.readFile(
  new URL(
    "../label-pdf/assets/NotoSansJP-VariableFont_wght.ttf",
    import.meta.url,
  ),
);

const CONTAINER_ID = "e8000000-0000-4000-8000-000000000001";
const USER_ID = "e9000000-0000-4000-8000-000000000001";

const containerRow = {
  display_id: "選果-2027-001-1",
  original_weight_kg: 18.4,
  ripening_lot_id: null,
  grade: { code: "M" },
  variety: { name: "ヘイワード" },
  sorting_result: {
    sorted_on: "2027-10-15",
    worker: { display_name: "大熊 太郎" },
    receiving_lot: { origin_name: "おおくま農園 第一圃場・A区画" },
  },
};

const ripeningContainerRow = {
  display_id: "追熟-2026-001-1",
  original_weight_kg: 8.0,
  ripening_lot_id: "d1000000-0000-4000-8000-000000000001",
  grade: null,
  variety: null,
  sorting_result: null,
};

const ripeningLabelRow: RipeningLabelRow = {
  container_id: CONTAINER_ID,
  display_id: "追熟-2026-001-1",
  weight_kg: 8.0,
  location_name: "追熟庫",
  variety_name: "ヘイワード",
  grade_code: "L",
  injection_at: "2026-09-01T10:00:00Z",
  planned_removal_at: "2026-09-04T09:00:00Z",
  planned_completion_at: "2026-09-20T09:00:00Z",
  orchard_names: "おおくま農園",
  allocations: [
    {
      order_id: "47000000-0000-0000-0000-000000000001",
      order_number: "ORD-S2-001",
      allocation_type: "order",
      allocated_weight_kg: 6,
    },
    {
      order_id: null,
      order_number: null,
      allocation_type: "reserve",
      allocated_weight_kg: 2,
    },
  ],
};

const sortingLabelBatchRow: SortingLabelBatchRow = {
  sorting_result_id: "e7000000-0000-4000-8000-000000000001",
  display_id: "選果-2027-001",
  containers: [
    {
      container_id: CONTAINER_ID,
      display_id: "選果-2027-001-1",
      weight_kg: 18.4,
      grade_code: "M",
      variety_name: "ヘイワード",
      origin_name: "おおくま農園 第一圃場・A区画",
      sorted_on: "2027-10-15",
      worker_name: "大熊 太郎",
    },
    {
      container_id: "e8000000-0000-4000-8000-000000000002",
      display_id: "選果-2027-001-2",
      weight_kg: 16.2,
      grade_code: "L",
      variety_name: "ヘイワード",
      origin_name: "おおくま農園 第一圃場・A区画",
      sorted_on: "2027-10-15",
      worker_name: "大熊 太郎",
    },
  ],
};

interface FakeConfig {
  user?: { id: string } | null;
  userError?: unknown;
  profile?: QueryResult<{ id: string }>;
  container?: QueryResult<unknown>;
  ripening?: QueryResult<unknown>;
  sortingBatch?: QueryResult<unknown>;
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
          data: {
            user: config.user === undefined ? { id: USER_ID } : config.user,
          },
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
    rpc(fn: string, _params: Record<string, unknown>) {
      const result = fn === "sorting_labels_get"
        ? config.sortingBatch ?? { data: sortingLabelBatchRow, error: null }
        : config.ripening ?? { data: ripeningLabelRow, error: null };
      return {
        maybeSingle: <T>() => Promise.resolve(result as QueryResult<T>),
      };
    },
  };
}

function handlerWith(config: FakeConfig) {
  return createHandler({
    sortingFontBytes,
    ripeningFontBytes,
    createClient: () => fakeClient(config),
  });
}

function getRequest(
  headers: Record<string, string> = { Authorization: "Bearer token" },
) {
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
  assert(
    exposed.includes("X-Label-Layout-Version"),
    "layout version must be exposed",
  );
  assert(
    exposed.includes("Content-Disposition"),
    "content disposition must be exposed",
  );
  assertEquals(res.headers.get("X-Label-Layout-Version"), "2");
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
  const res = await handlerWith({ profile: { data: null, error: null } })(
    getRequest(),
  );
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
  const res = await handlerWith({ container: { data: null, error: null } })(
    getRequest(),
  );
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

// Sorting-result batch tests --------------------------------------------------

function batchRequest() {
  return new Request("http://localhost/label-pdf", {
    method: "POST",
    headers: {
      Authorization: "Bearer token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      sorting_result_id: sortingLabelBatchRow.sorting_result_id,
      expected_page_count: sortingLabelBatchRow.containers.length,
    }),
  });
}

Deno.test("sorting result returns one combined A5 PDF", async () => {
  const res = await handlerWith({})(batchRequest());
  assertEquals(res.status, 200);
  const pdf = await PDFDocument.load(await res.arrayBuffer());
  assertEquals(pdf.getPageCount(), 2);
  assertEquals(res.headers.get("X-Label-Page-Count"), "2");
  assert(
    (res.headers.get("Content-Disposition") ?? "").includes("-labels.pdf"),
  );
});

Deno.test("sorting result rejects a page-count mismatch", async () => {
  const request = new Request("http://localhost/label-pdf", {
    method: "POST",
    headers: {
      Authorization: "Bearer token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      sorting_result_id: sortingLabelBatchRow.sorting_result_id,
      expected_page_count: 3,
    }),
  });
  const res = await handlerWith({})(request);
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error.code, "LABEL_COUNT_MISMATCH");
});

Deno.test("sorting result with no labels returns 404", async () => {
  const res = await handlerWith({
    sortingBatch: { data: null, error: null },
  })(batchRequest());
  assertEquals(res.status, 404);
  assertEquals((await res.json()).error.code, "SORTING_RESULT_NOT_FOUND");
});

Deno.test("request rejects both container and sorting result ids", async () => {
  const res = await handlerWith({})(
    new Request("http://localhost/label-pdf", {
      method: "POST",
      headers: {
        Authorization: "Bearer token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        container_id: CONTAINER_ID,
        sorting_result_id: sortingLabelBatchRow.sorting_result_id,
        expected_page_count: sortingLabelBatchRow.containers.length,
      }),
    }),
  );
  assertEquals(res.status, 400);
});

// Ripening container tests (S3-08) -------------------------------------------

function ripeningHandlerWith(config: FakeConfig) {
  return createHandler({
    sortingFontBytes,
    ripeningFontBytes,
    createClient: () =>
      fakeClient({
        ...config,
        container: config.container ??
          { data: ripeningContainerRow, error: null },
      }),
  });
}

Deno.test("ripening container returns a PDF via ripening_label_get", async () => {
  const res = await ripeningHandlerWith({})(getRequest());
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Content-Type"), "application/pdf");
  const body = new Uint8Array(await res.arrayBuffer());
  assert(body.length > 0, "non-empty PDF returned for ripening container");
  assertEquals(String.fromCharCode(...body.subarray(0, 5)), "%PDF-");
});

Deno.test("ripening RPC not found returns 404", async () => {
  const res = await ripeningHandlerWith({
    ripening: { data: null, error: null },
  })(getRequest());
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.error.code, "CONTAINER_NOT_FOUND");
});

Deno.test("ripening RPC error returns 500", async () => {
  const res = await ripeningHandlerWith({
    ripening: { data: null, error: { message: "connection reset" } },
  })(getRequest());
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error.code, "UNEXPECTED");
});
