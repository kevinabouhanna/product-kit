#!/bin/bash
# Runs every test in this folder. Usage: tests/run.sh
cd "$(dirname "$0")" || exit 1
status=0
for t in test-product-kit.sh test-docs-kit.sh; do
  echo "=== $t"
  ./"$t" || status=1
done
[ "$status" -eq 0 ] && echo "=== Every test passed." || echo "=== Some tests failed."
exit "$status"
