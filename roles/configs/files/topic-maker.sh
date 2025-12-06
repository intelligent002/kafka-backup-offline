#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# VIEW (logging patterns)
# =========================================================
log_info()  { echo "[STARTER] $*" >&2; }
log_error() { echo "[STARTER] ERROR: $*" >&2; }

# =========================================================
# MODEL (all heavy logic)
# =========================================================
# ------------------------------
# Static Configuration ENV
# ------------------------------
TOPIC_MAKER_ANTI_STORM_SLEEP="${TOPIC_MAKER_ANTI_STORM_SLEEP:-600}"
TOPIC_MAKER_AUTO_CREATE="${TOPIC_MAKER_AUTO_CREATE:-true}"
TOPIC_MAKER_BROKERS="${TOPIC_MAKER_BROKERS:-}"
TOPIC_MAKER_CONFIG="${TOPIC_MAKER_CONFIG:-/mnt/shared/config/kraft.properties}"
TOPIC_MAKER_DEBUG="${TOPIC_MAKER_DEBUG:-false}"
TOPIC_MAKER_KAFKA_DELAY="${TOPIC_MAKER_KAFKA_DELAY:-3}"
TOPIC_MAKER_KAFKA_RETRIES="${TOPIC_MAKER_KAFKA_RETRIES:-5}"
TOPIC_MAKER_TCP_DELAY="${TOPIC_MAKER_TCP_DELAY:-3}"
TOPIC_MAKER_TCP_RETRIES="${TOPIC_MAKER_TCP_RETRIES:-30}"
TOPIC_MAKER_TOPICS="${TOPIC_MAKER_TOPICS:-__connect_offset:50:3,__connect_config:1:3,__connect_status:5:3}"

# prevent restart storm
sleep_and_quit() {
  log_error "Sleeping for [$TOPIC_MAKER_ANTI_STORM_SLEEP] seconds before exit to avoid restart storm..."
  sleep $TOPIC_MAKER_ANTI_STORM_SLEEP
  exit 1
}

# minimum sanity
if [[ -z "$TOPIC_MAKER_BROKERS" ]]; then
  log_error "TOPIC_MAKER_BROKERS is required (e.g. host1:9093,host2:9093)."
  sleep_and_quit
fi
# ------------------------------------------------------------
# Low-level executor
#   - runs command
#   - captures stdout, stderr, rc
#   - exits on HARD failures (TLS, SASL, PKIX, etc.)
# ------------------------------------------------------------
executor() {
  local __outvar="$1"
  local __errvar="$2"
  local __rcvar="$3"
  shift 3

  local out_file err_file rc
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  if "$@" >"$out_file" 2>"$err_file"; then
    rc=0
  else
    rc=$?
  fi

  local stdout_content stderr_content
  stdout_content="$(cat "$out_file")"
  stderr_content="$(cat "$err_file")"

  rm -f "$out_file" "$err_file"

  if [[ "$TOPIC_MAKER_DEBUG" == "true" ]]; then
    echo "STDOUT: [$stdout_content]"
    echo "STDERR: [$stderr_content]"
    echo "EXIT:   [$rc]"
  fi

  # --- HARD FAILURE detection: fatal, non-retryable ---
  if [[ -n "$stderr_content" ]]; then
    case "$stderr_content" in
      *"SSLHandshakeException"*|\
      *"SSLException"*|\
      *"ValidatorException"*|\
      *"PKIX path building failed"*|\
      *"unable to find valid certification path"*|\
      *"unknown_ca"*|\
      *"certificate_unknown"*|\
      *"SASL authentication failed"*|\
      *"SaslAuthenticationException"*|\
      *"AuthenticationException"*|\
      *"Invalid SASL mechanism"*|\
      *"Keystore was tampered"*|\
      *"password was incorrect"*|\
      *"UnrecoverableKeyException"*|\
      *"Failed to load SSL keystore"*|\
      *"Failed to load SSL truststore"*|\
      *"InvalidTopicException"*|\
      *"Unrecognized option"*|\
      *"Unknown command"*|\
      *"Error processing command"*|\
      *"InvalidReplicationFactorException"*)
        log_error "Fatal error while executing command."
        log_error "STDERR: $stderr_content"
        sleep_and_quit
        ;;
    esac
  fi

  printf -v "$__outvar" '%s' "$stdout_content"
  printf -v "$__errvar" '%s' "$stderr_content"
  printf -v "$__rcvar" '%s' "$rc"
}

# ------------------------------------------------------------
# Broker selection (TCP readiness)
# ------------------------------------------------------------
model_select_broker() {
  local IFS=','

  # create brokers list out of brokers passed in
  read -ra BROKER_LIST <<< "$TOPIC_MAKER_BROKERS"

  # count the brokers for further usage
  BROKER_COUNT=${#BROKER_LIST[@]}

  for ((attempt=1; attempt<=TOPIC_MAKER_TCP_RETRIES; attempt++)); do
    for entry in "${BROKER_LIST[@]}"; do
      local host="${entry%%:*}"
      local port="${entry##*:}"

      if bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        log_info "Checking TCP connectivity [$host:$port] ... [$attempt/$TOPIC_MAKER_TCP_RETRIES] OK"
        SELECTED_BROKER="$host:$port"
        log_info "Selected broker: [$SELECTED_BROKER]"
        return 0
      else
        log_info "Checking TCP connectivity [$host:$port] ... [$attempt/$TOPIC_MAKER_TCP_RETRIES] FAILED"
      fi
    done

    sleep "$TOPIC_MAKER_TCP_DELAY"
  done

  log_error "No reachable brokers found after [$TOPIC_MAKER_TCP_RETRIES] attempts!"
  sleep_and_quit
}

# ------------------------------------------------------------
# Topic model functions (with retries)
# ------------------------------------------------------------

# Returns 0 if topic exists, 1 if not (after retries)
model_topic_exists() {
  local t="$1"
  local OUT ERR RC

  for ((i=1; i<=TOPIC_MAKER_KAFKA_RETRIES; i++)); do
    executor OUT ERR RC \
      bash -c '
        /opt/kafka/bin/kafka-topics.sh \
          --bootstrap-server "$1" \
          --command-config "$2" \
          --list
      ' _ "$SELECTED_BROKER" "$TOPIC_MAKER_CONFIG"

    if (( RC != 0 )); then
      log_info "Topic [$t] presence check ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] FAILED (rc=$RC)"
      sleep "$TOPIC_MAKER_KAFKA_DELAY"
      continue
    fi

    if grep -Fxq "$t" <<< "$OUT"; then
      log_info "Topic [$t] presence check ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] OK"
      return 0
    fi

    log_info "Topic [$t] not yet present ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] RETRY"
    sleep "$TOPIC_MAKER_KAFKA_DELAY"
  done

  log_error "Topic [$t] presence validation failed after $TOPIC_MAKER_KAFKA_RETRIES attempts"
  return 1
}

# Returns 0 on successful create (or already exists), 1 on soft failure
model_topic_create() {
  local t="$1" p="$2" r="$3"
  local OUT ERR RC

  for ((i=1; i<=TOPIC_MAKER_KAFKA_RETRIES; i++)); do
    executor OUT ERR RC \
      bash -c '
        /opt/kafka/bin/kafka-topics.sh \
          --bootstrap-server "$1" \
          --command-config "$2" \
          --create \
          --if-not-exists \
          --topic "$3" \
          --partitions "$4" \
          --replication-factor "$5" \
          --config cleanup.policy=compact
      ' _ "$SELECTED_BROKER" "$TOPIC_MAKER_CONFIG" "$t" "$p" "$r"

    if (( RC == 0 )); then
      log_info "Topic [$t] creation ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] OK"
      return 0
    fi

    log_info "Topic [$t] creation ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] FAILED (rc=$RC), retrying"
    sleep "$TOPIC_MAKER_KAFKA_DELAY"
  done

  log_error "Topic [$t] creation failed after $TOPIC_MAKER_KAFKA_RETRIES attempts"
  return 1
}

# Returns full describe output to stdout on success, 1 on failure
model_topic_metadata() {
  local t="$1"
  local OUT ERR RC

  for ((i=1; i<=TOPIC_MAKER_KAFKA_RETRIES; i++)); do
    executor OUT ERR RC \
      bash -c '
        /opt/kafka/bin/kafka-topics.sh \
          --bootstrap-server "$1" \
          --command-config "$2" \
          --describe --topic "$3"
      ' _ "$SELECTED_BROKER" "$TOPIC_MAKER_CONFIG" "$t"

    if (( RC != 0 )); then
      log_info "Topic [$t] metadata fetch ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] FAILED (rc=$RC)"
      sleep "$TOPIC_MAKER_KAFKA_DELAY"
      continue
    fi

    if printf '%s\n' "$OUT" | grep -q 'Configs:'; then
      log_info "Topic [$t] metadata fetch ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] OK"
      printf '%s\n' "$OUT"
      return 0
    fi

    log_info "Topic [$t] metadata not yet available ... [$i/$TOPIC_MAKER_KAFKA_RETRIES] RETRY"
    sleep "$TOPIC_MAKER_KAFKA_DELAY"
  done

  log_error "Topic [$t] metadata fetching failed after $TOPIC_MAKER_KAFKA_RETRIES attempts"
  return 1
}

# ------------------------------------------------------------
# Topic orchestration (create + validate)
# ------------------------------------------------------------

topic_create() {
  local topic="$1" partitions="$2" replication_factor="$3"

  if (( replication_factor > BROKER_COUNT )); then
    log_error "Topic [$topic] the replication factor [$replication_factor] is above broker count [$BROKER_COUNT]"
    sleep_and_quit
  fi

  log_info "Topic [$topic] presence validation started:"
  if model_topic_exists "$topic"; then
    log_info "Topic [$topic] presence validation is done, topic is present."
    return 0
  else
    log_info "Topic [$topic] presence validation is done, topic is absent."
  fi

  if [[ "$TOPIC_MAKER_AUTO_CREATE" != "true" ]]; then
    log_info "Topic [$topic] creation skipped, since TOPIC_MAKER_AUTO_CREATE is disabled."
    sleep_and_quit
  fi

  log_info "Topic [$topic] creation started:"
  if model_topic_create "$topic" "$partitions" "$replication_factor"; then
    log_info "Topic [$topic] creation is done, topic should be present."
  else
    log_error "Topic [$topic] creation is done, failed to create."
    sleep_and_quit
  fi

  log_info "Topic [$topic] presence validation after creation started:"
  if model_topic_exists "$topic"; then
    log_info "Topic [$topic] presence validation after creation is done, topic is present."
  else
    log_error "Topic [$topic] presence validation after creation is done, topic is absent after creation."
    sleep_and_quit
  fi
}

topic_validate() {
  local topic="$1"
  local expected_partitions="$2"
  local expected_replication_factor="$3"
  local raw_meta meta partitions replication_factor cleanup errors

  log_info "Topic [$topic] configuration fetching started:"

  if ! raw_meta="$(model_topic_metadata "$topic")"; then
    log_error "Topic [$topic] configuration fetching is done, unable to fetch metadata."
    sleep_and_quit
  fi

  meta="$(printf '%s\n' "$raw_meta" | grep 'Configs:' | head -n 1)"

  if [[ -z "$meta" ]]; then
    log_error "Topic [$topic] configuration fetching is done, unable to parse metadata."
    sleep_and_quit
  else
    log_info "Topic [$topic] configuration fetching is done, metadata fetched."
  fi

  # Parse fields
  log_info "Topic [$topic] configuration validation started:"

  partitions="$(printf '%s\n' "$meta" | sed -n 's/.*PartitionCount:[[:space:]]*\([0-9]*\).*/\1/p')"
  replication_factor="$(printf '%s\n' "$meta" | sed -n 's/.*ReplicationFactor:[[:space:]]*\([0-9]*\).*/\1/p')"
  cleanup="$(printf '%s\n' "$meta" | sed -n 's/.*cleanup.policy=\([^,]*\).*/\1/p')"

  errors=0

  if [[ -z "$partitions" || -z "$replication_factor" ]]; then
    log_error "Topic [$topic] configuration parsing failure: missing partitions or replication factor"
    sleep_and_quit
  fi

  if (( partitions < expected_partitions )); then
    log_error "Topic [$topic] configuration validation failure: partitions mismatch - expected [$expected_partitions], got [$partitions]"
    errors=$((errors+1))
  else
    log_info "Topic [$topic] configuration validation pass: property [partitions]         value is [$partitions]"
  fi

  if (( replication_factor < expected_replication_factor )); then
    log_error "Topic [$topic] configuration validation failure: replication factor mismatch - expected [$expected_replication_factor], got [$replication_factor]"
    errors=$((errors+1))
  else
    log_info "Topic [$topic] configuration validation pass: property [replication factor] value is [$replication_factor]"
  fi

  if [[ "$cleanup" != "compact" ]]; then
    log_error "Topic [$topic] configuration validation failure: cleanup.policy mismatch - expected [compact], got [$cleanup]"
    errors=$((errors+1))
  else
    log_info "Topic [$topic] configuration validation pass: property [cleanup policy]     value is [$cleanup]"
  fi

  if (( errors == 0 )); then
    log_info "Topic [$topic] configuration validation is done."
  else
    log_error "Topic [$topic] configuration validation is done, failures detected."
    sleep_and_quit
  fi
}

function prepare_topics() {
  local IFS

  REQUIRED_TOPICS=()
  IFS=',' read -ra __topic_entries <<< "$TOPIC_MAKER_TOPICS"
  for entry in "${__topic_entries[@]}"; do
    REQUIRED_TOPICS+=("$entry")
  done
}

# =========================================================
# CONTROLLER (Thin, readable flow)
# =========================================================
function controller() {
  local IFS
  echo "---------------------------------------------------------------"
  log_info "Kafka Connect Startup Initializer"

  # choose the broker to work with
  model_select_broker

  # prepare topics array
  prepare_topics

  # iterate over topics and act
  for line in "${REQUIRED_TOPICS[@]}"; do
    IFS=':' read -r NAME PART REPLICATION_FACTOR <<< "$line"

    topic_create   "$NAME" "$PART" "$REPLICATION_FACTOR"
    topic_validate "$NAME" "$PART" "$REPLICATION_FACTOR"
  done

  log_info "All topics verified"
  echo "---------------------------------------------------------------"
}

controller
