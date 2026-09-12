import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { createHandler, Job } from "./handler.ts";
import {
  googleCalendar,
  ServiceAccount,
  SyncError,
  tokenProvider,
} from "./google.ts";

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
let account: ServiceAccount = { client_email: "", private_key: "" };
try {
  account = JSON.parse(Deno.env.get("GOOGLE_CALENDAR_SERVICE_ACCOUNT") ?? "{}");
} catch { /* reported per job */ }
const sync = googleCalendar(
  Deno.env.get("GOOGLE_CALENDAR_ID") ?? "",
  Deno.env.get("APP_BASE_URL") ?? "",
  tokenProvider(account),
);
Deno.serve(createHandler({
  secret: Deno.env.get("CALENDAR_SYNC_TOKEN") ?? "",
  store: {
    async claim() {
      const { data, error } = await client.rpc("calendar_sync_claim", {
        batch_size: 5,
      });
      if (error) throw new SyncError("DB_UNAVAILABLE");
      return data as Job[];
    },
    async finish(job, errorCode) {
      const { data, error } = await client.rpc("calendar_sync_finish", {
        task_id_value: job.task.id,
        lease_token_value: job.lease_token,
        revision_value: job.revision,
        error_code_value: errorCode,
      });
      if (error) throw new SyncError("DB_UNAVAILABLE");
      return data as boolean;
    },
  },
  sync,
}));
