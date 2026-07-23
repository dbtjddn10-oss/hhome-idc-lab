#!/bin/bash

set -euo pipefail

SOURCE_DIR="/home/sungwoo/docker-nginx/html"
BACKUP_DIR="/home/sungwoo/home-idc-lab/backups"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_FILE="$BACKUP_DIR/nginx-html-$TIMESTAMP.tar.gz"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "FAIL: Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

tar -czf "$BACKUP_FILE" \
  -C "$(dirname "$SOURCE_DIR")" \
  "$(basename "$SOURCE_DIR")"

cd "$BACKUP_DIR"

sha256sum "$(basename "$BACKUP_FILE")" \
  > "$(basename "$BACKUP_FILE").sha256"

find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'nginx-html-*.tar.gz' -o -name 'nginx-html-*.tar.gz.sha256' \) \
  -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
