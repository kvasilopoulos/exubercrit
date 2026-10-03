# Simulates Monte Carlo critical values for every sample size n up to N, for
# each requested lag, and writes one small file per (lag, n) to OUT_DIR
# (data/lag<L>/n<N>.bin.xz -- layout in common.R).
#
# Why this is fast: exubercore::radf_nested() (exuber:::rls_nested) returns
# the statistics for every n in [n_min, N] from a single O(N^2) sweep of one
# path, because the windows that a smaller n uses are prefix windows of the
# full path. For each lag the cost is therefore 2000 paths of length N, and
# N = 4000 takes about 0.2 s (lag 0) to 4 s (lag 4) per path. A separate
# O(n^3) simulation for each n would take far longer. Every n of a lag shares
# the same 2000 paths. The tables are nested, and each is still exactly the
# null distribution at its n. They are smoother in n than independently
# simulated tables would be. The same per-replication seeds are used for
# every lag, so the lags share paths too.
#
# The reduction is the same as in radf_mc_cv(): adf, sadf and gsadf are
# quantiles across replications, and bsadf_cv holds the quantiles of
# cummax(badf) at each position.
#
# n_min for each lag is the smallest n whose PSY window leaves at least one
# residual degree of freedom in the first window and gives at least two
# windows overall. Below that, radf_mc_cv() itself fails.
#
# Flush: once the files of a lag are written, they are synced to the bucket
# if credentials are in the environment (see common.R), so each lag is
# uploaded as soon as it is done. Running the script again skips lags whose
# files all exist.
#
#   Rscript scripts/simulate-crit.R [lags] [N] [nrep] [ncores]
#   Rscript scripts/simulate-crit.R 0:4 4000        # default
#   Rscript scripts/simulate-crit.R 1 600 2000 8

SCRIPT_DIR <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])))
source(file.path(SCRIPT_DIR, "common.R"))
args <- commandArgs(trailingOnly = TRUE)
LAGS   <- if (length(args) >= 1) eval(parse(text = args[1])) else 0:4
N      <- if (length(args) >= 2) as.integer(args[2]) else 4000L
NREP   <- if (length(args) >= 3) as.integer(args[3]) else 2000L
NCORES <- if (length(args) >= 4) as.integer(args[4]) else max(1L, parallel::detectCores() - 2L)
SEED   <- 123L
PKG    <- normalizePath(file.path(SCRIPT_DIR, "..", "..", "exuber"))  # development tree, because rls_nested() is not on CRAN yet
LOG    <- file.path(SCRIPT_DIR, "..", ".runs", "simulate-crit.log")
PCNT   <- c(0.9, 0.95, 0.99)

log_msg <- function(fmt, ...) {
  msg <- sprintf("[%s] %s", format(Sys.time()), sprintf(fmt, ...))
  cat(msg, "\n", sep = ""); cat(msg, "\n", sep = "", file = LOG, append = TRUE)
}

suppressMessages(pkgload::load_all(PKG, quiet = TRUE))

n_min_for <- function(lag) {
  n <- 6L
  repeat {
    m <- psy_minw(n)
    if (m >= lag + 3L && n - m - lag >= 2L) return(n)
    n <- n + 1L
  }
}

# The seed of each replication is fixed up front, so the results do not
# depend on how replications are split across workers, or on NCORES at all.
set.seed(SEED)
seeds <- sample.int(.Machine$integer.max, NREP)

one_rep <- function(i, lag, N, minw, n_min) {
  set.seed(seeds[i])
  y <- cumsum(rnorm(N))
  rls_nested(unroot(y, lag = lag), minw, n_min, lag)
}

cl <- parallel::makeCluster(NCORES)
on.exit(parallel::stopCluster(cl), add = TRUE)
parallel::clusterCall(cl, function(pkg) suppressMessages(pkgload::load_all(pkg, quiet = TRUE)), PKG)
parallel::clusterExport(cl, "seeds")
log_msg("=== starting: lags %s, N=%d, nrep=%d, cores=%d, seed=%d ===",
        paste(range(LAGS), collapse = ":"), N, NREP, NCORES, SEED)

for (lag in LAGS) {
  n_min <- n_min_for(lag)
  ns <- n_min:N
  lag_dir <- file.path(OUT_DIR, sprintf("lag%d", lag))
  dir.create(lag_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- file.path(lag_dir, sprintf("n%d.bin.xz", ns))
  if (all(file.exists(paths))) { log_msg("lag %d: all %d files present, skipping", lag, length(ns)); next }

  minw <- as.integer(vapply(ns, psy_minw, numeric(1)))
  R <- N - 1L - lag
  t0 <- Sys.time()
  res <- parallel::parSapply(cl, seq_len(NREP), one_rep, lag = lag, N = N, minw = minw, n_min = n_min)
  log_msg("lag %d: simulated %d paths of N=%d in %.1f min", lag, NREP, N,
          as.numeric(difftime(Sys.time(), t0, units = "mins")))

  w0 <- t(res[seq_len(R), , drop = FALSE])          # nrep x R : badf row W(0, e)
  gsadf <- res[R + seq_along(ns), , drop = FALSE]    # K x nrep
  rm(res)
  q <- function(x) quantile(x, probs = PCNT, na.rm = TRUE, names = FALSE)

  t0 <- Sys.time()
  for (m in sort(unique(minw))) {
    # bsadf_cv for every n with this window: quantiles of cummax(badf), where
    # badf for n is W(0, m..R_n). All such n share the same prefix, so we
    # compute cummax and the quantiles once for each m and slice them per n.
    cm <- t(apply(w0[, m:R, drop = FALSE], 1, cummax))          # nrep x (R-m+1)
    qm <- t(apply(cm, 2, q))                                     # (R-m+1) x 3
    for (k in which(minw == m)) {
      n <- ns[k]; Rn <- n - 1L - lag; nrows <- Rn - m + 1L
      write_crit_bin_xz(
        n = n, minw = m, lag = lag,
        adf_cv = q(w0[, Rn]),
        sadf_cv = q(cm[, nrows]),
        gsadf_cv = q(gsadf[k, ]),
        bsadf_cv = qm[seq_len(nrows), , drop = FALSE],
        path = paths[k]
      )
    }
  }
  log_msg("lag %d: wrote %d tables (n %d..%d) in %.1f min", lag, length(ns), n_min, N,
          as.numeric(difftime(Sys.time(), t0, units = "mins")))

  if (UPLOAD) {
    ok <- sync_to_bucket(lag_dir, sprintf("crit/lag%d", lag))
    log_msg("lag %d: %s", lag, if (ok) "synced to bucket" else "UPLOAD FAILED (kept locally; sync by hand, see README)")
  }
}
log_msg("=== finished ===")
