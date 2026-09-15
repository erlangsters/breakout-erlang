#!/usr/bin/env bash
set -euo pipefail

Root="$(cd "$(dirname "$0")" && pwd)"
cd "$Root"

rebar3 compile

BuildDir="$Root/_build/default"
PaArgs=()
for AppDir in "$BuildDir"/lib/*/ebin "$BuildDir"/checkouts/*/ebin; do
  if [ -d "$AppDir" ]; then
    PaArgs+=(-pa "$AppDir")
  fi
done

if [ "${#PaArgs[@]}" -eq 0 ]; then
  echo "Unable to locate compiled application ebin directories" >&2
  exit 1
fi

exec erl -noshell \
  "${PaArgs[@]}" \
  -eval 'begin {ok, _} = application:ensure_all_started(breakout), breakout:start(), halt(0) end.'
