#!/bin/bash

CONTAINER_NAME="home-idc-nginx"
URL="http://127.0.0.1:8080"
STATUS=0

echo "===== Home IDC Health Check ====="
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo

echo "[CPU / UPTIME]"
uptime
echo

echo "[MEMORY]"
free -h
echo

echo "[DISK]"
df -h /
echo

echo "[DOCKER]"
if systemctl is-active --quiet docker; then
  echo "OK: Docker service is running"
else
  echo "FAIL: Docker service is not running"
  STATUS=1
fi

if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
  echo "OK: $CONTAINER_NAME is running"
else
  echo "FAIL: $CONTAINER_NAME is not running"
  STATUS=1
fi

echo
echo "[HTTP]"
if curl -fsS "$URL" >/dev/null; then
  echo "OK: $URL responded"
else
  echo "FAIL: $URL did not respond"
  STATUS=1
fi

echo
echo "Exit code: $STATUS"
exit "$STATUS"
