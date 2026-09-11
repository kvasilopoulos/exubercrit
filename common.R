# Shared by simulate-crit.R and upload-crit.R.

OUT_DIR <- Sys.getenv("EXUBER_CRIT_DIR", "out")
BUCKET <- Sys.getenv("EXUBER_BUCKET_NAME", Sys.getenv("AWS_S3_BUCKET_NAME", "critical-values-kwz4n3ykp"))
ENDPOINT <- Sys.getenv("EXUBER_BUCKET_ENDPOINT", Sys.getenv("AWS_ENDPOINT_URL", "https://t3.storageapi.dev"))
# Uploads happen only when bucket credentials are in the environment:
#   eval "$(railway bucket credentials -b exuber-storage)"
UPLOAD <- nzchar(Sys.getenv("AWS_ACCESS_KEY_ID"))

# Fixed little-endian binary layout, parseable with readBin()/np.frombuffer
# in R/Python without pickle or RDS overhead. badf_cv is NOT stored: it's
# always the constant PWY asymptotic tiling (see radf_mc_cv()), trivially
# reconstructed client-side, so storing it would just double the payload
# for zero information.
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
  file.rename(tmp, path)  # atomic-ish: a half-written file never looks "done"
}

# One `aws s3 sync` of a local directory to its bucket prefix (only transfers
# what's new). Returns TRUE on success; never throws, so a network blip
# doesn't lose local results.
sync_to_bucket <- function(local_dir, prefix) {
  status <- system2("aws", c(
    "s3", "sync", local_dir, sprintf("s3://%s/%s/", BUCKET, prefix),
    "--endpoint-url", ENDPOINT, "--region", "auto", "--only-show-errors"
  ))
  status == 0L
}
