// index.tsx (Bun v1.3 runtime)
import { Hono } from "hono@4";
import { cors } from 'hono/cors';
import { S3Client } from "bun";

const app = new Hono();

app.use("/*", cors());

const s3 = new S3Client({
  accessKeyId: import.meta.env.BUCKET_ACCESS_KEY_ID,
  secretAccessKey: import.meta.env.BUCKET_SECRET_ACCESS_KEY,
  bucket: import.meta.env.BUCKET_NAME,
  endpoint: import.meta.env.BUCKET_ENDPOINT,
  region: "auto",
});

// Read-only allowlist: this endpoint serves only these two fixed objects
// and never an arbitrary bucket key.
const CRIT_OBJECTS: Record<string, { key: string; type: string }> = {
  r: { key: "radf_crit2.rds", type: "application/octet-stream" },
  py: { key: "radf_crit2.pkl.xz", type: "application/x-xz" },
};

app.get("/", (c) => c.text("Hello world!"));
app.get("/api/health", (c) => c.json({ status: "ok" }));

async function serveKey(c: any, key: string, type: string) {
  const file = s3.file(key);
  // Cheap existence check (HEAD). It avoids streaming a broken response
  // after the headers have already been sent.
  if (!(await file.exists())) {
    return c.json({ error: "not found" }, 404);
  }
  // Stream straight from the bucket to the client without buffering in
  // process memory, so cost and RAM do not grow with file size or
  // concurrency. This must be file.stream() and not the S3File itself,
  // because Bun rejects `new Response(s3File, init)` with
  // ERR_INVALID_ARG_TYPE.
  return new Response(file.stream(), {
    headers: {
      "Content-Type": type,
      "Cache-Control": "public, max-age=604800, immutable",
    },
  });
}

app.get("/crit/:lang", async (c) => {
  const spec = CRIT_OBJECTS[c.req.param("lang")];
  if (!spec) return c.json({ error: "unknown critical-value object" }, 404);
  return serveKey(c, spec.key, spec.type);
});

// Per-(n, lag) extended table, one small object per combination (see
// scripts/simulate-crit.R). This route is also read-only and bounds-checked,
// and it can address only keys under crit/lag*/n*.bin.xz.
const N_MIN = 6;
const N_MAX = 5000;
const LAG_MAX = 4;

app.get("/crit2/:lag/:n", async (c) => {
  const lag = Number(c.req.param("lag"));
  const n = Number(c.req.param("n"));
  if (!Number.isInteger(lag) || lag < 0 || lag > LAG_MAX) {
    return c.json({ error: `lag must be an integer in [0, ${LAG_MAX}]` }, 400);
  }
  if (!Number.isInteger(n) || n < N_MIN || n > N_MAX) {
    return c.json({ error: `n must be an integer in [${N_MIN}, ${N_MAX}]` }, 400);
  }
  return serveKey(c, `crit/lag${lag}/n${n}.bin.xz`, "application/x-xz");
});

Bun.serve({
  port: import.meta.env.PORT ?? 3000,
  fetch: app.fetch,
});
