import { CalendarTask, SyncError } from "./google.ts";
export interface Job {
  task: CalendarTask;
  lease_token: string;
  revision: number;
}
export interface SyncStore {
  claim(): Promise<Job[]>;
  finish(job: Job, errorCode: string | null): Promise<boolean>;
}
export interface Dependencies {
  secret: string;
  store: SyncStore;
  sync(task: CalendarTask): Promise<void>;
}
async function matches(actual: string, expected: string): Promise<boolean> {
  if (!expected) return false;
  const hash = (value: string) =>
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  const [a, b] = await Promise.all([hash(actual), hash(expected)]);
  return new Uint8Array(a).reduce(
    (difference, byte, i) => difference | (byte ^ new Uint8Array(b)[i]),
    0,
  ) === 0;
}
export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    if (
      !await matches(
        request.headers.get("x-calendar-sync-token") ?? "",
        deps.secret,
      )
    ) return new Response(null, { status: 401 });
    try {
      const jobs = await deps.store.claim();
      let synced = 0, failed = 0, stale = 0;
      // Claim at most five jobs; bounded requests finish inside the five-minute lease.
      const results = await Promise.allSettled(jobs.map(async (job) => {
        let code: string | null = null;
        try {
          await deps.sync(job.task);
        } catch (error) {
          code = error instanceof SyncError ? error.code : "SYNC_UNAVAILABLE";
        }
        const accepted = await deps.store.finish(job, code);
        if (!accepted) stale++;
        else if (code) failed++;
        else synced++;
      }));
      if (results.some((result) => result.status === "rejected")) {
        throw new SyncError("DB_UNAVAILABLE");
      }
      return Response.json({ claimed: jobs.length, synced, failed, stale });
    } catch {
      // Never log request bodies, provider errors, tokens, task notes or PII.
      return Response.json({ error: "SYNC_WORKER_UNAVAILABLE" }, {
        status: 503,
      });
    }
  };
}
