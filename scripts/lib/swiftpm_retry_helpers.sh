#!/usr/bin/env bash

swiftpm_retryable_build_failure() {
  local log_file="$1"
  grep -Eq "input file '.*' was modified during the build" "$log_file"
}

run_swiftpm_command_with_retry() {
  local description="$1"
  shift

  local max_attempts="${CPAPER_SWIFTPM_RETRY_ATTEMPTS:-3}"
  local attempt=1
  local log_dir
  local log_file
  local exit_status

  while true; do
    log_dir="$(mktemp -d "${TMPDIR%/}/cpaper-swiftpm-retry.XXXXXX")" || return 1
    log_file="${log_dir}/swiftpm.log"
    : > "$log_file" || {
      rm -rf "$log_dir"
      return 1
    }

    if "$@" > >(tee "$log_file") 2> >(tee -a "$log_file" >&2); then
      rm -rf "$log_dir"
      return 0
    fi
    exit_status=$?

    if [ "$attempt" -ge "$max_attempts" ] || ! swiftpm_retryable_build_failure "$log_file"; then
      rm -rf "$log_dir"
      return "$exit_status"
    fi

    echo "Detected known SwiftPM transient build noise while ${description}; retrying (${attempt}/${max_attempts})..." >&2
    rm -rf "$log_dir"
    attempt=$((attempt + 1))
    sleep 1
  done
}
