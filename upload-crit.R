# Bulk upload of everything under out/ to the bucket -- the catch-up path
# for anything simulate-crit.R couldn't flush at the time (no creds, network
# down). A plain recursive sync: aws diffs against what's already remote and
# only transfers what's new.
#
# Requires bucket credentials in the environment and the aws CLI on PATH:
#   eval "$(railway bucket credentials -b exuber-storage)"
#   Rscript upload-crit.R
source("common.R")
if (!UPLOAD) stop("no AWS_ACCESS_KEY_ID in the environment -- see the comment above")
for (d in list.files(OUT_DIR, pattern = "^lag[0-9]+$")) {
  if (!sync_to_bucket(file.path(OUT_DIR, d), paste0("crit/", d))) stop("aws s3 sync failed for ", d)
}
cat("done\n")
