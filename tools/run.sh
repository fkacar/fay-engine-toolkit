#!/bin/sh
# Eksik kütüphaneleri kurar, yerel arm64 için derler ve çalıştırır.
# Oyun: ./run.sh       Editör: ./run.sh editor       Testler: ./run.sh test
# Yalnızca derlemek için sona build eklenir: ./run.sh build, ./run.sh editor build
set -e
cd "$(dirname "$0")/../../.."

HAXE_SERIES=4.3
TOOLKIT=libs/scene-toolkit
HL_DIR=$TOOLKIT/vendor/hashlink/mac-arm64
HXML=build-mac.hxml
C_DIR=bin/c
OUTPUT=bin/game
TESTS=

if [ "$1" = "editor" ]; then
  HXML=editor-mac.hxml
  C_DIR=bin/editor-c
  OUTPUT=bin/editor
  shift
  if [ ! -f "$HL_DIR/hlimgui.hdll" ]; then
    echo "hlimgui eksik. Önce sh $TOOLKIT/tools/build-hlimgui.sh çalıştır." >&2
    exit 1
  fi
elif [ "$1" = "test" ]; then
  HXML=$TOOLKIT/tests-mac.hxml
  C_DIR=bin/tests-c
  OUTPUT=bin/tests
  TESTS=1
  shift
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "Bu script Apple Silicon içindir." >&2
  exit 1
fi

if ! command -v haxe >/dev/null 2>&1; then
  echo "Haxe bulunamadı. $HAXE_SERIES sürümünü https://haxe.org/download/ adresinden kur." >&2
  exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
  echo "clang bulunamadı. xcode-select --install komutunu çalıştır." >&2
  exit 1
fi

HAXE_VERSION=$(haxe --version)
case "$HAXE_VERSION" in
  "$HAXE_SERIES".*) ;;
  *) echo "Uyarı: Haxe $HAXE_VERSION kurulu, ekip $HAXE_SERIES kullanıyor." >&2 ;;
esac

# Kütüphane sürümleri common.hxml'de sabittir, burada tekrar yazılmaz.
for lib in $(sed -n 's/^-lib //p' common.hxml); do
  if ! haxelib path "$lib" >/dev/null 2>&1; then
    haxelib install common.hxml --always
    break
  fi
done

haxe "$HXML"

# Mac'te HashLink sanal makinesi çalışmaz: Haxe C üretir, clang yerel uygulamaya derler.
# -O2 (karar 4 Kasım 2026): -O0'a göre yaklaşık 7 kat hızlı (fizik ölçümü), derleme 8 sn uzun; -g hata ayıklamayı korur.
# -fwrapv şart: Haxe'nin Int'i taşınca sarar; C'de işaretli taşma tanımsızdır, eniyileme açıkken karma ve rastgele
# sayı döngüleri bozulur (FNV tohumu her metinde 0 çıkıyordu).
clang -std=c11 -O2 -g -w -fwrapv -I "$C_DIR" -I "$HL_DIR/include" -o "$OUTPUT" "$C_DIR/main.c" \
  -Wl,-rpath,"@executable_path/../$HL_DIR" -Wl,-dead_strip_dylibs \
  "$HL_DIR/libhl.dylib" "$HL_DIR"/*.hdll

if [ "$1" != "build" ]; then
  # Testlerde ardından Heaps'in matematik türlerini isteyen testler (yorumlayıcıda, tests/heaps).
  if [ -n "$TESTS" ]; then
    "$OUTPUT"
    exec haxe "$TOOLKIT/tests-heaps.hxml"
  fi
  exec "$OUTPUT"
fi
