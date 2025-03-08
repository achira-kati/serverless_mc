#!/usr/bin/env bash

mkdir -p "$TS_STATE_DIR"

# Now start Python
exec python3 -u /usr/local/bin/redis_controller.py
