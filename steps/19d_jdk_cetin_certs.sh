#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 19d: CETIN CA certificates in mise JDKs"

# JDK z mise (Temurin) mají vlastní cacerts a systémovým kotvám ze stepu 00d
# nevěří. Nová JDK ošetří mise hook postinstall (config/mise/config.toml,
# nasazuje step 20); tenhle step dorovná ta, co už na stroji jsou — třeba
# nainstalovaná dřív, než hook existoval. Skript je idempotentní (otisk SHA-256).
# Volá se kopie z repa: ~/scripts plní až step 30.
"$SCRIPT_DIR/scripts/jdk-cetin-certs.sh" | while IFS= read -r line; do log_info "$line"; done

log_info "Step 19d done"
