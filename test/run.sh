#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

lua test/test-selection.lua
