#!/usr/bin/env bash
# Checks that the app answers 200 at the given address.
# Usage: ./scripts/health-check.sh https://my-app.azurewebsites.net/health

set -euo pipefail

#url="$1"
#status=$(curl --silent --output /dev/null --write-out "%{http_code}" "$url")

url="${1:?Give the address as the first argument}"
expected="${2:-}" #***
ATTEMPTS="${ATTEMPTS:-10}"
DELAY="${DELAY:-5}"

echo "Checking $url"
#***
if [ -n "$expected" ]; then
  echo "The answer must contain: $expected"
fi

echo "At most $ATTEMPTS attempts, $DELAY seconds apart"

for attempt in $(seq 1 "$ATTEMPTS"); do
  answer=$(curl --silent --write-out " %{http_code}" --max-time 10 "$url" || true)
  status="${answer##* }"
  # status=$(curl --silent --output /dev/null --write-out "%{http_code}" \
  #   --max-time 10 "$url" || true)

  #***
 if [ "$status" = "200" ] && [[ "$answer" == *"$expected"* ]]; then
  #if [ "$status" = "200" ]; then
    echo "OK: the app answered 200 on attempt $attempt."
    exit 0
  fi

  #***
  if [ "$status" = "200" ]; then
    status="200, but without the expected text"
  fi

  # No point waiting after the last attempt: there is nothing left to wait for.
  if [ "$attempt" -lt "$ATTEMPTS" ]; then
    echo "Attempt $attempt of $ATTEMPTS: status $status. Waiting $DELAY s..."
    sleep "$DELAY"
  else
    echo "Attempt $attempt of $ATTEMPTS: status $status. Giving up."
  fi
done

echo "FAILED: the app never answered 200 after $ATTEMPTS attempts."
exit 1
