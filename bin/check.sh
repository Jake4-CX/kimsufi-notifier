#!/bin/bash
#
# Check OVH Eco (including Kimsufi) server availability

set -eu

SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE}") && pwd -P)
DEBUG=false

ENDPOINT="ovh-eu"
OPSGENIE_API_URL="https://api.opsgenie.com/v2/alerts"
TELEGRAM_API_URL="https://api.telegram.org"
HEALTHCHECKS_IO_API_URL="https://hc-ping.com"

echo_stderr() {
  echo >&2 "$@"
}

usage() {
  bin_name=$(basename "$0")
  echo_stderr "Usage: $bin_name"
  echo_stderr
  echo_stderr "Check OVH Eco (including Kimsufi) server availability"
  echo_stderr
  echo_stderr "Arguments"
  echo_stderr "  -p, --plan-code  Plan code to check (e.g. 24ska01)"
  echo_stderr "  -d, --datacenters    Comma-separated list of datacenters to check availability for (default all)"
  echo_stderr "                         Example values: bhs, ca, de, fr, fra, gb, gra, lon, pl, rbx, sbg, waw (non exhaustive list)"
  echo_stderr "  -e, --endpoint       OVH API endpoint (default: ovh-eu)"
  echo_stderr "                         Allowed values: ovh-eu, ovh-ca, ovh-us"
  echo_stderr "      --debug          Enable debug mode (default: false)"
  echo_stderr "  -h, --help           Display this help message"
  echo_stderr
  echo_stderr "  Arguments can also be set as environment variables see config.env.example"
  echo_stderr "  Command line arguments take precedence over environment variables"
  echo_stderr
  echo_stderr "Environment variables"
  echo_stderr "    DISCORD_WEBHOOK       Webhook URL to use for Discord notification service"
  echo_stderr "    GOTIFY_URL            URL to use for Gotify notification service"
  echo_stderr "    GOTIFY_TOKEN          token to use for Gotify notification service"
  echo_stderr "    GOTIFY_PRIORITY       priority for Gotify notification service"
  echo_stderr "    OPSGENIE_API_KEY      API key for OpsGenie to receive notifications"
  echo_stderr "    TELEGRAM_BOT_TOKEN    Bot token for Telegram to receive notifications"
  echo_stderr "    TELEGRAM_CHAT_ID      Chat ID for Telegram to receive notifications"
  echo_stderr "    HEALTHCHECKS_IO_UUID  UUID for healthchecks.io to ping after successful run"
  echo_stderr
  echo_stderr "Example:"
  echo_stderr "  $bin_name --plan-code 24ska01"
  echo_stderr "  $bin_name --plan-code 24ska01 --datacenters fr,gra,rbx,sbg"
}

notify_discord() {
  local message="$1"
  if [ -z ${DISCORD_WEBHOOK+x} ]; then
    return
  fi

  BODY="{\"content\": \"$message\"}"

  echo_stderr "> sending Discord notification"
  RESULT="$(curl -sSX POST -H "Content-Type: application/json" "$DISCORD_WEBHOOK" -d "$BODY")"

  if $DEBUG; then
    echo_stderr "$RESULT"
  fi

  if echo "$RESULT" | $JQ_BIN -e .message &>/dev/null; then
    echo "$RESULT"
    echo_stderr "> failed Discord notification"
  else
    echo_stderr "> sent Discord notification"
  fi
}

order_server() {
  echo_stderr "> Ordering server $PLAN_CODE in $1 datacenter(s)"
  bin/order.sh --plan-code "$PLAN_CODE" --datacenter "$1" --item-configuration region=europe

  # Exit after successful order
  echo_stderr "> Server ordered successfully!"
  notify_discord "Server ordered successfully!"
  exit 0
}

main() {
  source "${SCRIPT_DIR}/../config.env"
  source "${SCRIPT_DIR}/common.sh"

  install_tools

  ARGS=$(getopt -o 'd:e:hp:' --long 'datacenters:,debug,endpoint:,help,plan-code:' -- "$@")
  eval set -- "$ARGS"
  while true; do
    case "$1" in
    -d | --datacenters)
      DATACENTERS="$2"
      shift 2
      continue
      ;;
    --debug)
      DEBUG=true
      shift 1
      continue
      ;;
    -e | --endpoint)
      ENDPOINT="$2"
      shift 2
      continue
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -p | --plan-code)
      PLAN_CODE="$2"
      shift 2
      continue
      ;;
    '--')
      shift
      break
      ;;
    *)
      echo_stderr 'Internal error!'
      exit 1
      ;;
    esac
  done

  if [ -z "${PLAN_CODE-}" ]; then
    echo_stderr "Error: PLAN_CODE is not set"
    echo_stderr
    usage
    exit 1
  fi

  OVH_URL="${OVH_API_ENDPOINTS["$ENDPOINT"]}/dedicated/server/datacenter/availabilities?planCode=${PLAN_CODE}"

  DATACENTERS_MESSAGE=""
  if [ -n "${DATACENTERS-}" ]; then
    OVH_URL="${OVH_URL}&datacenters=${DATACENTERS}"
    DATACENTERS_MESSAGE="'$DATACENTERS' datacenter(s)"
  else
    DATACENTERS_MESSAGE="all datacenters"
  fi

  while true; do
    # Fetch availability from API
    echo_stderr "> checking $PLAN_CODE availability in $DATACENTERS_MESSAGE"
    DATA="$(curl -Ss "${OVH_URL}")"

    if [ -z "$DATA" ] || ! echo "$DATA" | $JQ_BIN -e . &>/dev/null; then
      echo "> failed to fetch data from $OVH_URL"
      exit 1
    fi

    # Ping healthchecks.io if needed
    if [ -n "${HEALTHCHECKS_IO_UUID-}" ]; then
      curl -sS -o /dev/null "${HEALTHCHECKS_IO_API_URL}/${HEALTHCHECKS_IO_UUID}"
    fi

    # Check for datacenters availability
    if echo "$DATA" | $JQ_BIN -e '.[].datacenters[] | select(.availability != "unavailable")' &>/dev/null; then
      AVAILABLE_DATACENTERS="$(echo "$DATA" | $JQ_BIN -r '[.[].datacenters[] | select(.availability != "unavailable") | .datacenter] | unique | join(",")')"
      echo_stderr "> checked $PLAN_CODE available in $AVAILABLE_DATACENTERS datacenter(s)"

      # Send discord notification
      message="$PLAN_CODE is available in $AVAILABLE_DATACENTERS datacenter(s)"
      notify_discord "$message"

      # Order the server for each available datacenter
      IFS=',' read -r -a datacenter_array <<<"$AVAILABLE_DATACENTERS"
      for datacenter in "${datacenter_array[@]}"; do
        echo_stderr "> Ordering server $PLAN_CODE in '$datacenter' datacenter"
        notify_discord "Ordering server $PLAN_CODE in '$datacenter' datacenter"
        # order_server "$datacenter"
      done
    else
      echo_stderr "> checked $PLAN_CODE unavailable in $DATACENTERS_MESSAGE"
      # notify_discord "$PLAN_CODE is unavailable in $DATACENTERS_MESSAGE"
    fi

    # Wait for a specified interval before the next check
    sleep 5s
  done
}

main "$@"
