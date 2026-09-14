// Stateless A5 label PDF generation for sorted containers.
//
// Authorization happens inside the function: the caller's JWT is verified and
// all reads go through PostgREST with that JWT, so RLS decides visibility
// (gateway verify_jwt is disabled to let browser CORS preflights through).
// Request handling lives in handler.ts so it can be unit tested with injected
// fakes; this module only wires the real Supabase client and font bytes.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { createHandler, LabelClient } from "./handler.ts";

const sortingFontBytes = await Deno.readFile(
  new URL("./assets/NotoSansJP-SemiBold.ttf", import.meta.url),
);
const ripeningFontBytes = await Deno.readFile(
  new URL("./assets/NotoSansJP-VariableFont_wght.ttf", import.meta.url),
);

Deno.serve(
  createHandler({
    sortingFontBytes,
    ripeningFontBytes,
    appBaseUrl: Deno.env.get("APP_BASE_URL") ?? "",
    createClient: (authHeader) =>
      createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        {
          global: { headers: { Authorization: authHeader } },
          auth: { persistSession: false, autoRefreshToken: false },
        },
      ) as unknown as LabelClient,
  }),
);
