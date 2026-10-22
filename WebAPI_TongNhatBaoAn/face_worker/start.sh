#!/usr/bin/env bash
set -euo pipefail
python3 /opt/face-worker/worker.py &
worker_pid=$!
trap 'kill "$worker_pid" 2>/dev/null || true' EXIT INT TERM
# Core API stays available even if the optional face worker exits.
# Face endpoints fail closed with 503 when the worker is unavailable.
dotnet /app/WebAPI_TongNhatBaoAn.dll
