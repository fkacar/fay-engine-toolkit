#!/bin/sh
cd "$(dirname "$0")"
[ -f libs/scene-toolkit/tools/run.sh ] || git submodule update --init --recursive
exec libs/scene-toolkit/tools/run.sh "$@"
