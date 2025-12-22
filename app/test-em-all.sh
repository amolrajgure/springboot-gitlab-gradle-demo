#!/bin/sh

: ${HOST:=localhost}
: ${PORT:=8080}
: ${PROD_ID_REVS_RECS:=1}
: ${PROD_ID_NOT_FOUND:=13}
: ${PROD_ID_NO_RECS:=113}
: ${PROD_ID_NO_REVS:=213}

assertCurl() {
  expectedHttpCode="$1"
  curlCmd="$2 -w \"%{http_code}\""

  result=$(eval "$curlCmd")
  httpCode=$(echo "$result" | tail -c 4)
  RESPONSE=$(echo "$result" | sed '$ s/...$//')

  if [ "$httpCode" = "$expectedHttpCode" ]; then
    echo "Test OK (HTTP Code: $httpCode)"
  else
    echo "Test FAILED, EXPECTED: $expectedHttpCode, GOT: $httpCode"
    echo "Command: $curlCmd"
    echo "Response: $RESPONSE"
    exit 1
  fi
}

assertEqual() {
  expected="$1"
  actual="$2"

  if [ "$actual" = "$expected" ]; then
    echo "Test OK (actual value: $actual)"
  else
    echo "Test FAILED, EXPECTED: $expected, ACTUAL: $actual"
    exit 1
  fi
}

testUrl() {
  curl -ksf "$@" >/dev/null 2>&1
}

waitForService() {
  url="$1"
  echo "Waiting for $url"

  n=0
  until testUrl "$url"; do
    n=$((n + 1))
    if [ "$n" -ge 100 ]; then
      echo "Give up waiting for $url"
      exit 1
    fi
    sleep 3
  done

  echo "Service is up"
}

set -eu

echo "Start Tests: $(date)"
echo "HOST=$HOST"
echo "PORT=$PORT"

case "$*" in
  *start*)
    docker compose down --remove-orphans || true
    docker compose up -d
    ;;
esac

waitForService "http://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS"

assertCurl 200 "curl -s http://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS"
assertEqual "$PROD_ID_REVS_RECS" "$(echo "$RESPONSE" | jq .productId)"
assertEqual 3 "$(echo "$RESPONSE" | jq '.recommendations | length')"
assertEqual 3 "$(echo "$RESPONSE" | jq '.reviews | length')"

assertCurl 404 "curl -s http://$HOST:$PORT/product-composite/$PROD_ID_NOT_FOUND"
assertEqual "No product found for productId: $PROD_ID_NOT_FOUND" \
  "$(echo "$RESPONSE" | jq -r .message)"

assertCurl 200 "curl -s http://$HOST:$PORT/product-composite/$PROD_ID_NO_RECS"
assertEqual 0 "$(echo "$RESPONSE" | jq '.recommendations | length')"

assertCurl 200 "curl -s http://$HOST:$PORT/product-composite/$PROD_ID_NO_REVS"
assertEqual 0 "$(echo "$RESPONSE" | jq '.reviews | length')"

assertCurl 422 "curl -s http://$HOST:$PORT/product-composite/-1"
assertCurl 400 "curl -s http://$HOST:$PORT/product-composite/invalidProductId"

case "$*" in
  *stop*)
    docker compose down
    ;;
esac

echo "All tests OK: $(date)"
