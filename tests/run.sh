#!/bin/bash
# Runs every test in this folder. Usage: tests/run.sh
cd "$(dirname "$0")" || exit 1
status=0
for t in test-product-kit.sh test-docs-kit.sh test-lang-kit.sh test-shots-kit.sh; do
  echo "=== $t"
  ./"$t" || status=1
done
echo "=== test-generic.py"
python3 -I ./test-generic.py || status=1
[ "$status" -eq 0 ] && echo "=== Every test passed." || echo "=== Some tests failed."
exit "$status"
