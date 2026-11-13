#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_BINARY="$(mktemp "${TMPDIR:-/tmp}/sky-core-tests.XXXXXX")"
trap 'rm -f "$TEST_BINARY"' EXIT
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror "$TEST_DIR/core_tests.cpp" -o "$TEST_BINARY"
"$TEST_BINARY"
