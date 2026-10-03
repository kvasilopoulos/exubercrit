# Sourced by simulate-crit.R, which defines SCRIPT_DIR (this directory) so
# paths resolve regardless of the working directory.

OUT_DIR <- Sys.getenv("EXUBER_CRIT_DIR", file.path(SCRIPT_DIR, "..", "data"))
BUCKET <- Sys.getenv("EXUBER_BUCKET_NAME", Sys.getenv("AWS_S3_BUCKET_NAME", "critical-values-kwz4n3ykp"))
ENDPOINT <- Sys.getenv("EXUBER_BUCKET_ENDPOINT", Sys.getenv("AWS_ENDPOINT_URL", "https://t3.storageapi.dev"))
# Uploads happen only when bucket credentials are in the environment:
#   eval "$(railway bucket credentials -b exuber-storage)"
UPLOAD <- nzchar(Sys.getenv("AWS_ACCESS_KEY_ID"))

# Fixed little-endian binary layout, which readBin() in R and np.frombuffer
# in Python can parse without pickle or RDS overhead. badf_cv is not stored.
# It is always the constant PWY asymptotic tiling (see radf_mc_cv()), the
# client rebuilds it easily, and storing it would double the payload without
# adding information.
#   int32 x4:  n, minw, lag, nrows
#   float64 x3: adf_cv (90/95/99%)
#   float64 x3: sadf_cv
#   float64 x3: gsadf_cv
#   float64 x(nrows*3): bsadf_cv, row-major (row = time index, col = pcnt)
write_crit_bin_xz <- function(n, minw, lag, adf_cv, sadf_cv, gsadf_cv, bsadf_cv, path) {
  tmp <- paste0(path, ".part")  # write under a temp name, rename on success
  con <- xzfile(tmp, "wb", compression = 9)
  writeBin(as.integer(c(n, minw, lag, nrow(bsadf_cv))), con, size = 4L)
  writeBin(as.double(adf_cv), con)
  writeBin(as.double(sadf_cv), con)
  writeBin(as.double(gsadf_cv), con)
  writeBin(as.double(t(bsadf_cv)), con)
  close(con)
  file.rename(tmp, path)  # a half-written file never looks finished
}

# One `aws s3 sync` of a local directory to its bucket prefix, which
# transfers only what is new. Returns TRUE on success. It never throws, so a
# network failure does not lose local results. In that case, rerun the same
# aws command by hand (see the README).
sync_to_bucket <- function(local_dir, prefix) {
  status <- system2("aws", c(
    "s3", "sync", local_dir, sprintf("s3://%s/%s/", BUCKET, prefix),
    "--endpoint-url", ENDPOINT, "--region", "auto", "--only-show-errors"
  ))
  status == 0L
}
