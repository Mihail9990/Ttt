#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
terrain_binary="$(mktemp /tmp/sky-terrain-test.XXXXXX)"
trap 'rm -f "$terrain_binary"' EXIT
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Werror -pedantic Tests/terrain_tests.cpp -o "$terrain_binary"
"$terrain_binary"
