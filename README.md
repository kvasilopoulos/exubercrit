# crit

Producer side of the shared critical-value store that `exuber` (and,
planned, `pyexuber`) read from at runtime. The client is
`exuber/R/crit-bucket.R`; this directory holds everything that puts data
behind it.

```
common.R          binary layout writer + bucket sync helper, shared by the two scripts
simulate-crit.R   Monte Carlo for every n <= N per lag -> out/lag<L>/n<N>.bin.xz; syncs each lag when done
upload-crit.R     catch-up: aws s3 sync out/ -> s3://<bucket>/crit/             (needs bucket creds)
exuber-fn.ts      Railway function "exuber-fn": read-only proxy, GET /crit2/<lag>/<n>
```

Deployed at https://exuber.up.railway.app (alias https://exubercrit.kvasilopoulos.com).
Railway project `exuber`, bucket `exuber-storage`. Bounds enforced by the
proxy: lag 0–4, n 6–5000.

## Coverage (2026-09-11)

| lag | n         | status                              |
|-----|-----------|-------------------------------------|
| 0   | 6–600     | bundled in `exuber::radf_crit`, not in the bucket |
| 0   | 601–2000  | live                                |
| 0   | 2001–5000 | not simulated                       |
| 1–4 | any       | not simulated                       |

Anything not covered makes `radf()` (without a user-supplied `cv`) error
with "haven't been simulated yet". n_min(lag) is the smallest n whose PSY window leaves a residual degree of
freedom in the first window and >= 2 windows overall (6, 7, 9, 11, 15 for lag 0-4);
below that `radf_mc_cv()` itself fails.

## Workflow

```sh
eval "$(railway bucket credentials -b exuber-storage)"   # optional: flush each lag to the bucket as it lands
Rscript simulate-crit.R 0:4 4000        # lags, N, [nrep=2000], [ncores]; ~30 min total on 14 cores
Rscript upload-crit.R                   # only if a sync failed above
railway functions push -p exuber-fn.ts  # only if exuber-fn.ts changed
curl -sI https://exuber.up.railway.app/crit2/1/100 | head -1
```

`simulate-crit.R` needs the `exuber` dev tree next door (`../exuber`) for
`rls_nested()`, exubercore v0.2.0's single-sweep-per-path routine: every
n <= N for one lag comes from 2000 paths of length N, so the whole grid is
minutes, not months. All n of a lag (and all lags) share the same seeded
paths; the reduction is exactly `radf_mc_cv()`'s.

Binary layout (little-endian): `int32 x4: n, minw, lag, nrows` then
`float64 x3` each for adf/sadf/gsadf (90/95/99%), then `float64 x(nrows*3)`
bsadf row-major. `badf_cv` isn't stored (constant asymptotic tiling).
