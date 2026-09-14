// Request handling for the label-pdf function, separated from the Deno.serve
// entry point and the concrete Supabase client so it can be unit tested with
// injected fakes. The handler never writes to the database; print-state
// changes are the label_* PostgreSQL RPCs, so a failed or retried generation
// cannot leave inventory data inconsistent.
//
// S3-08: ripening containers are detected by the presence of ripening_lot_id.
// Their label data comes from the ripening_label_get RPC instead of the
// containers join, so the same entry point serves both label types.
import {
  buildReceivingLabelsPdf,
  buildRipeningLabelPdf,
  buildSortingLabelPdf,
  buildSortingLabelsPdf,
  LABEL_LAYOUT_VERSION,
  RipeningLabelData,
  SortingLabelData,
} from "./layout.ts";

// Response headers the browser client is allowed to read. Flutter Web uses the
// layout version for reproducibility diagnostics and Content-Disposition for
// the download filename, so both must be exposed across CORS.
const EXPOSED_HEADERS =
  "Content-Disposition, X-Label-Layout-Version, X-Label-Page-Count";

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-correlation-id",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Expose-Headers": EXPOSED_HEADERS,
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface ContainerLabelRow {
  display_id: string;
  original_weight_kg: number | string;
  ripening_lot_id: string | null;
  grade: { code: string } | null;
  variety: { name: string } | null;
  sorting_result: {
    sorted_on: string;
    worker: { display_name: string } | null;
    receiving_lot: { origin_name: string } | null;
  } | null;
}

// Shape returned by public.ripening_label_get(container_id_value).
export interface RipeningLabelRow {
  container_id: string;
  display_id: string;
  weight_kg: number | string;
  location_name: string | null;
  variety_name: string;
  grade_code: string;
  injection_at: string | null;
  planned_removal_at: string | null;
  planned_completion_at: string | null;
  orchard_names: string | null;
  allocations: Array<
    {
      order_id: string | null;
      order_number: string | null;
      allocation_type: string;
      allocated_weight_kg: number;
    }
  >;
}

export interface SortingLabelBatchContainerRow {
  container_id: string;
  display_id: string;
  weight_kg: number | string;
  grade_code: string;
  variety_name: string;
  origin_name: string;
  sorted_on: string;
  worker_name: string;
}

export interface SortingLabelBatchRow {
  sorting_result_id: string;
  display_id: string;
  containers: SortingLabelBatchContainerRow[];
}

export interface ReceivingLabelRow {
  id: string;
  display_id: string;
  received_on: string;
  origin_name: string;
  total_weight_kg: number | string;
  container_count: number;
  status: string;
  variety: { name: string } | null;
}

export interface QueryResult<T> {
  data: T | null;
  error: { message: string } | null;
}

// Minimal slice of the Supabase client the handler relies on. The real client
// and the test fakes both satisfy it.
export interface LabelQuery {
  select(columns: string): LabelQuery;
  eq(column: string, value: string): LabelQuery;
  maybeSingle<T = unknown>(): Promise<QueryResult<T>>;
}

export interface RpcQuery {
  maybeSingle<T = unknown>(): Promise<QueryResult<T>>;
}

export interface LabelClient {
  auth: {
    getUser(token: string): Promise<
      { data: { user: { id: string } | null } | null; error: unknown }
    >;
  };
  from(table: string): LabelQuery;
  rpc(fn: string, params: Record<string, unknown>): RpcQuery;
}

export interface HandlerDeps {
  sortingFontBytes: Uint8Array;
  ripeningFontBytes: Uint8Array;
  appBaseUrl: string;
  createClient(authHeader: string): LabelClient;
}

export function receivingSortingUrl(
  appBaseUrl: string,
  receivingLotId: string,
): string {
  const base = new URL(appBaseUrl);
  if (
    base.protocol !== "https:" || base.search || base.hash || base.username ||
    base.password || !UUID_PATTERN.test(receivingLotId)
  ) {
    throw new Error("APP_BASE_URL is not a valid HTTPS application URL");
  }
  return `${base.toString().replace(/\/$/, "")}/sorting/${receivingLotId}`;
}

function logEvent(fields: Record<string, unknown>): void {
  console.log(JSON.stringify({ fn: "label-pdf", ...fields }));
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  correlationId: string,
): Response {
  return new Response(
    JSON.stringify({
      error: { code, message },
      correlation_id: correlationId || null,
    }),
    {
      status,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    },
  );
}

export function createHandler(
  deps: HandlerDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const startedAt = performance.now();
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: CORS_HEADERS });
    }

    let containerId = "";
    let sortingResultId = "";
    let receivingLotId = "";
    let expectedPageCount: number | null = null;
    let correlationId = req.headers.get("x-correlation-id") ?? "";
    if (req.method === "GET") {
      const params = new URL(req.url).searchParams;
      containerId = params.get("container_id") ?? "";
      sortingResultId = params.get("sorting_result_id") ?? "";
      receivingLotId = params.get("receiving_lot_id") ?? "";
      const rawExpectedPageCount = params.get("expected_page_count");
      if (rawExpectedPageCount !== null) {
        expectedPageCount = Number(rawExpectedPageCount);
      }
    } else if (req.method === "POST") {
      try {
        const body = await req.json();
        containerId = typeof body?.container_id === "string"
          ? body.container_id
          : "";
        sortingResultId = typeof body?.sorting_result_id === "string"
          ? body.sorting_result_id
          : "";
        receivingLotId = typeof body?.receiving_lot_id === "string"
          ? body.receiving_lot_id
          : "";
        if (body?.expected_page_count !== undefined) {
          expectedPageCount = Number(body.expected_page_count);
        }
        if (typeof body?.correlation_id === "string") {
          correlationId = body.correlation_id;
        }
      } catch {
        return errorResponse(
          400,
          "VALIDATION_FAILED",
          "JSON本文を読み取れません。",
          correlationId,
        );
      }
    } else {
      return errorResponse(
        405,
        "VALIDATION_FAILED",
        "GETまたはPOSTで呼び出してください。",
        correlationId,
      );
    }

    const hasContainerId = containerId !== "";
    const hasSortingResultId = sortingResultId !== "";
    const hasReceivingLotId = receivingLotId !== "";
    if (
      Number(hasContainerId) + Number(hasSortingResultId) +
            Number(hasReceivingLotId) !== 1 ||
      (hasContainerId && !UUID_PATTERN.test(containerId)) ||
      (hasSortingResultId && !UUID_PATTERN.test(sortingResultId)) ||
      (hasReceivingLotId && !UUID_PATTERN.test(receivingLotId))
    ) {
      logEvent({ outcome: "invalid_request", correlation_id: correlationId });
      return errorResponse(
        400,
        "VALIDATION_FAILED",
        "container_id、sorting_result_id、receiving_lot_idのいずれか1つを正しく指定してください。",
        correlationId,
      );
    }
    if (
      (hasSortingResultId || hasReceivingLotId) &&
      (expectedPageCount === null ||
        !Number.isSafeInteger(expectedPageCount) || expectedPageCount <= 0)
    ) {
      logEvent({ outcome: "invalid_request", correlation_id: correlationId });
      return errorResponse(
        400,
        "VALIDATION_FAILED",
        "expected_page_count を1以上の整数で指定してください。",
        correlationId,
      );
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const bearerToken = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (bearerToken === "") {
      logEvent({ outcome: "auth_required", correlation_id: correlationId });
      return errorResponse(
        401,
        "AUTH_REQUIRED",
        "ログインが必要です。",
        correlationId,
      );
    }

    try {
      const client = deps.createClient(authHeader);

      const { data: userData, error: userError } = await client.auth.getUser(
        bearerToken,
      );
      if (userError || !userData?.user) {
        logEvent({ outcome: "auth_required", correlation_id: correlationId });
        return errorResponse(
          401,
          "AUTH_REQUIRED",
          "ログインが必要です。",
          correlationId,
        );
      }

      // RLS only exposes their own profile to active users. A query error means
      // the lookup itself failed (PostgREST/network), which is a retryable
      // server fault, not a permission decision — surface it as UNEXPECTED.
      const { data: profile, error: profileError } = await client
        .from("profiles")
        .select("id")
        .eq("id", userData.user.id)
        .maybeSingle<{ id: string }>();
      if (profileError) {
        throw new Error(`profile lookup failed: ${profileError.message}`);
      }
      if (!profile) {
        logEvent({ outcome: "auth_forbidden", correlation_id: correlationId });
        return errorResponse(
          403,
          "AUTH_FORBIDDEN",
          "この操作を行う権限がありません。",
          correlationId,
        );
      }

      if (hasReceivingLotId) {
        const { data: lot, error: lotError } = await client
          .from("receiving_lots")
          .select(
            "id, display_id, received_on, origin_name, total_weight_kg, " +
              "container_count, status, variety:varieties(name)",
          )
          .eq("id", receivingLotId)
          .maybeSingle<ReceivingLabelRow>();
        if (lotError) {
          throw new Error(`receiving lot query failed: ${lotError.message}`);
        }
        if (!lot) {
          logEvent({
            outcome: "not_found",
            receiving_lot_id: receivingLotId,
            correlation_id: correlationId,
          });
          return errorResponse(
            404,
            "RECEIVING_LOT_NOT_FOUND",
            "対象の受入ロットが見つかりません。",
            correlationId,
          );
        }
        if (lot.status !== "awaiting_sorting") {
          logEvent({
            outcome: "conflict",
            receiving_lot_id: receivingLotId,
            status: lot.status,
            correlation_id: correlationId,
          });
          return errorResponse(
            409,
            "RECEIVING_LOT_NOT_AVAILABLE",
            "この受入ロットはすでに選果済みです。選果対象一覧を確認してください。",
            correlationId,
          );
        }
        if (lot.container_count !== expectedPageCount) {
          logEvent({
            outcome: "page_count_mismatch",
            receiving_lot_id: receivingLotId,
            expected_page_count: expectedPageCount,
            actual_page_count: lot.container_count,
            correlation_id: correlationId,
          });
          return errorResponse(
            409,
            "LABEL_COUNT_MISMATCH",
            "登録したコンテナ数とラベル枚数が一致しません。登録結果を確認してください。",
            correlationId,
          );
        }
        const sortingUrl = receivingSortingUrl(
          deps.appBaseUrl,
          receivingLotId,
        );
        const pdf = await buildReceivingLabelsPdf({
          receivingLotDisplayId: lot.display_id,
          receivedOn: lot.received_on,
          originName: lot.origin_name,
          varietyName: lot.variety?.name ?? "",
          totalWeightKg: Number(lot.total_weight_kg).toFixed(2),
          containerCount: lot.container_count,
          sortingUrl,
        }, deps.sortingFontBytes);
        logEvent({
          outcome: "ok",
          receiving_lot_id: receivingLotId,
          page_count: lot.container_count,
          correlation_id: correlationId,
          layout_version: LABEL_LAYOUT_VERSION,
          pdf_bytes: pdf.byteLength,
          duration_ms: Math.round(performance.now() - startedAt),
        });
        return new Response(pdf.buffer as ArrayBuffer, {
          headers: {
            ...CORS_HEADERS,
            "Content-Type": "application/pdf",
            "Content-Disposition":
              `inline; filename="receiving-labels.pdf"; filename*=UTF-8''${
                encodeURIComponent(lot.display_id)
              }-receiving-labels.pdf`,
            "Cache-Control": "no-store",
            "X-Label-Layout-Version": String(LABEL_LAYOUT_VERSION),
            "X-Label-Page-Count": String(lot.container_count),
          },
        });
      }

      if (hasSortingResultId) {
        const { data: batch, error: batchError } = await client
          .rpc("sorting_labels_get", {
            sorting_result_id_value: sortingResultId,
          })
          .maybeSingle<SortingLabelBatchRow>();
        if (batchError) {
          throw new Error(`sorting_labels_get failed: ${batchError.message}`);
        }
        if (
          !batch || !Array.isArray(batch.containers) ||
          batch.containers.length === 0
        ) {
          logEvent({
            outcome: "not_found",
            sorting_result_id: sortingResultId,
            correlation_id: correlationId,
          });
          return errorResponse(
            404,
            "SORTING_RESULT_NOT_FOUND",
            "対象の選果結果またはラベルが見つかりません。",
            correlationId,
          );
        }
        if (batch.containers.length !== expectedPageCount) {
          logEvent({
            outcome: "page_count_mismatch",
            sorting_result_id: sortingResultId,
            expected_page_count: expectedPageCount,
            actual_page_count: batch.containers.length,
            correlation_id: correlationId,
          });
          return errorResponse(
            409,
            "LABEL_COUNT_MISMATCH",
            "選果結果とラベル枚数が一致しません。選果対象を再読み込みしてください。",
            correlationId,
          );
        }
        const labels: SortingLabelData[] = batch.containers.map((row) => ({
          containerDisplayId: row.display_id,
          originName: row.origin_name,
          varietyName: row.variety_name,
          gradeCode: row.grade_code,
          netWeightKg: Number(row.weight_kg).toFixed(2),
          sortedOn: row.sorted_on,
          workerName: row.worker_name,
        }));
        const pdf = await buildSortingLabelsPdf(labels, deps.sortingFontBytes);
        logEvent({
          outcome: "ok",
          sorting_result_id: sortingResultId,
          page_count: labels.length,
          correlation_id: correlationId,
          layout_version: LABEL_LAYOUT_VERSION,
          pdf_bytes: pdf.byteLength,
          duration_ms: Math.round(performance.now() - startedAt),
        });
        return new Response(pdf.buffer as ArrayBuffer, {
          headers: {
            ...CORS_HEADERS,
            "Content-Type": "application/pdf",
            "Content-Disposition":
              `inline; filename="labels.pdf"; filename*=UTF-8''${
                encodeURIComponent(batch.display_id)
              }-labels.pdf`,
            "Cache-Control": "no-store",
            "X-Label-Layout-Version": String(LABEL_LAYOUT_VERSION),
            "X-Label-Page-Count": String(labels.length),
          },
        });
      }

      // Fetch container to detect its origin type (sorting vs. ripening).
      const { data: row, error: rowError } = await client
        .from("containers")
        .select(
          `display_id, original_weight_kg, ripening_lot_id,
           grade:grades(code),
           variety:varieties(name),
           sorting_result:sorting_results(
             sorted_on,
             worker:workers(display_name),
             receiving_lot:receiving_lots(origin_name)
           )`,
        )
        .eq("id", containerId)
        .maybeSingle<ContainerLabelRow>();
      if (rowError) {
        throw new Error(`container query failed: ${rowError.message}`);
      }
      if (!row) {
        logEvent({
          outcome: "not_found",
          container_id: containerId,
          correlation_id: correlationId,
        });
        return errorResponse(
          404,
          "CONTAINER_NOT_FOUND",
          "対象のコンテナが見つかりません。",
          correlationId,
        );
      }

      let pdf: Uint8Array;
      let displayId: string;

      if (row.ripening_lot_id) {
        // ── Ripening container (S3-08) ──────────────────────────────────────
        const { data: ripRow, error: ripError } = await client
          .rpc("ripening_label_get", { container_id_value: containerId })
          .maybeSingle<RipeningLabelRow>();
        if (ripError) {
          throw new Error(`ripening_label_get failed: ${ripError.message}`);
        }
        if (!ripRow) {
          logEvent({
            outcome: "not_found",
            container_id: containerId,
            correlation_id: correlationId,
          });
          return errorResponse(
            404,
            "CONTAINER_NOT_FOUND",
            "対象の追熟コンテナが見つかりません。",
            correlationId,
          );
        }
        const labelData: RipeningLabelData = {
          containerDisplayId: ripRow.display_id,
          orchardNames: ripRow.orchard_names ?? "",
          varietyName: ripRow.variety_name,
          gradeCode: ripRow.grade_code,
          netWeightKg: Number(ripRow.weight_kg).toFixed(2),
          injectionAt: ripRow.injection_at ?? "",
          plannedRemovalAt: ripRow.planned_removal_at ?? null,
          plannedCompletionAt: ripRow.planned_completion_at ?? null,
          locationName: ripRow.location_name ?? "",
          allocations: ripRow.allocations.map((a) => ({
            allocationType: a.allocation_type,
            orderNumber: a.order_number,
            weightKg: Number(a.allocated_weight_kg).toFixed(2),
          })),
        };
        pdf = await buildRipeningLabelPdf(labelData, deps.ripeningFontBytes);
        displayId = ripRow.display_id;
      } else {
        // ── Sorting container (S1-08) ───────────────────────────────────────
        if (!row.sorting_result) {
          logEvent({
            outcome: "not_found",
            container_id: containerId,
            correlation_id: correlationId,
          });
          return errorResponse(
            404,
            "CONTAINER_NOT_FOUND",
            "対象のコンテナが見つかりません。",
            correlationId,
          );
        }
        const labelData: SortingLabelData = {
          containerDisplayId: row.display_id,
          originName: row.sorting_result.receiving_lot?.origin_name ?? "",
          varietyName: row.variety?.name ?? "",
          gradeCode: row.grade?.code ?? "",
          netWeightKg: Number(row.original_weight_kg).toFixed(2),
          sortedOn: row.sorting_result.sorted_on,
          workerName: row.sorting_result.worker?.display_name ?? "",
        };
        pdf = await buildSortingLabelPdf(labelData, deps.sortingFontBytes);
        displayId = row.display_id;
      }

      logEvent({
        outcome: "ok",
        container_id: containerId,
        correlation_id: correlationId,
        layout_version: LABEL_LAYOUT_VERSION,
        pdf_bytes: pdf.byteLength,
        duration_ms: Math.round(performance.now() - startedAt),
      });
      return new Response(pdf.buffer as ArrayBuffer, {
        headers: {
          ...CORS_HEADERS,
          "Content-Type": "application/pdf",
          "Content-Disposition":
            `inline; filename="label.pdf"; filename*=UTF-8''${
              encodeURIComponent(displayId)
            }.pdf`,
          "Cache-Control": "no-store",
          "X-Label-Layout-Version": String(LABEL_LAYOUT_VERSION),
        },
      });
    } catch (cause) {
      logEvent({
        outcome: "error",
        container_id: containerId,
        sorting_result_id: sortingResultId,
        correlation_id: correlationId,
        message: cause instanceof Error ? cause.message : String(cause),
        duration_ms: Math.round(performance.now() - startedAt),
      });
      return errorResponse(
        500,
        "UNEXPECTED",
        "ラベルの生成に失敗しました。再試行してください。",
        correlationId,
      );
    }
  };
}
