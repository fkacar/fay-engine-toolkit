#!/bin/sh
cd "$(dirname "$0")"
[ -f libs/scene-toolkit/tools/push.sh ] || git submodule update --init --recursive
exec libs/scene-toolkit/tools/push.sh "$@"
