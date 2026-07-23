#!/bin/bash

set -euo pipefail

export HOME="/home/sungwoo"
export PATH="/usr/local/bin:/usr/bin:/bin"

BACKUP_SCRIPT="/home/sungwoo/home-idc-lab/scripts/backup-nginx.sh"
BACKUP_DIR="/home/sungwoo/home-idc-lab/backups"
BUCKET="s3://home-idc-backup-lab-20260723-k7m4"
S3_PREFIX="nginx-backups"
PROFILE="home-idc-s3-backup"
LOCK_FILE="/tmp/home-idc-s3-upload.lock"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
  echo "FAIL: Another S3 upload job is already running" >&2
  exit 1
fi

echo "===== Home IDC S3 Backup Upload ====="
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo

"$BACKUP_SCRIPT"

LATEST_BACKUP="$(
  find "$BACKUP_DIR" -maxdepth 1 -type f \
    -name 'nginx-html-*.tar.gz' \
    -printf '%T@ %p\n' |
  sort -nr |
  head -n 1 |
  cut -d' ' -f2-
)"

if [ -z "$LATEST_BACKUP" ] || [ ! -f "$LATEST_BACKUP" ]; then
  echo "FAIL: Backup file was not found" >&2
  exit 1
fi

CHECKSUM_FILE="${LATEST_BACKUP}.sha256"
BACKUP_NAME="$(basename "$LATEST_BACKUP")"

echo "Uploading: $BACKUP_NAME"

/usr/local/bin/aws s3 cp \
  "$LATEST_BACKUP" \
  "$BUCKET/$S3_PREFIX/$BACKUP_NAME" \
  --profile "$PROFILE" \
  --only-show-errors

if [ -f "$CHECKSUM_FILE" ]; then
  /usr/local/bin/aws s3 cp \
    "$CHECKSUM_FILE" \
    "$BUCKET/$S3_PREFIX/$(basename "$CHECKSUM_FILE")" \
    --profile "$PROFILE" \
    --only-show-errors
else
  echo "WARN: Checksum file was not found: $CHECKSUM_FILE" >&2
fi

echo
echo "S3 upload completed: $BUCKET/$S3_PREFIX/$BACKUP_NAME"
