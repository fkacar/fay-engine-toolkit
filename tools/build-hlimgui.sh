#!/bin/sh
# hlimgui eklentisini Mac arm64 için derler ve HashLink kitaplıklarının yanına koyar.
# Çıktı depoya girer, her Mac'te yeniden derlemek gerekmez.
set -e
cd "$(dirname "$0")/../../.."

ROOT=$(pwd)
HL_DIR="$ROOT/libs/scene-toolkit/vendor/hashlink/mac-arm64"
OBJ_DIR="$ROOT/bin/hlimgui-obj"
EXTENSION=libs/scene-toolkit/third_party/hlimgui/extension

if [ ! -f "$EXTENSION/lib/imgui/imgui.h" ]; then
  git -C libs/scene-toolkit submodule update --init --recursive third_party/hlimgui
fi
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"
cd "$EXTENSION"

# Dosya adı sona eklenir, script'te $0 HL_DIR, $1 OBJ_DIR, $2 kaynak dosyadır.
ls *.cpp lib/imgui/*.cpp addons/node_editor/*.cpp lib/imgui-node-editor/*.cpp addons/markdown/*.cpp |
  xargs -n 1 -P "$(sysctl -n hw.ncpu)" sh -c '
    clang++ -arch arm64 -std=c++14 -O2 -fPIC -w \
      -DIMGUI_USER_CONFIG="\"../../imgui_config.h\"" \
      -I"$0/include" -Ilib/imgui -I. -c "$2" -o "$1/$(echo "$2" | tr / _).o"
  ' "$HL_DIR" "$OBJ_DIR"

clang++ -arch arm64 -dynamiclib -install_name @rpath/hlimgui.hdll -o "$HL_DIR/hlimgui.hdll" \
  "$OBJ_DIR"/*.o "$HL_DIR/libhl.dylib" -framework ApplicationServices

echo "Hazır: libs/scene-toolkit/vendor/hashlink/mac-arm64/hlimgui.hdll"
