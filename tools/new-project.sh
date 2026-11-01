#!/bin/sh
# Şablondan yeni oyun projesi oluşturur. Windows'ta Git Bash ile çalışır.
# Kullanım: sh libs/scene-toolkit/tools/new-project.sh ../yeni-oyun
set -e

if [ $# -ne 1 ]; then
  echo "Kullanım: new-project.sh <hedef klasör>" >&2
  exit 1
fi

TOOLKIT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=$1

if [ -e "$TARGET" ]; then
  echo "Hedef zaten var: $TARGET" >&2
  exit 1
fi

mkdir -p "$TARGET/libs/scene-toolkit"
cp -R "$TOOLKIT/template/." "$TARGET/"
mv "$TARGET/gitignore.txt" "$TARGET/.gitignore"
mv "$TARGET/gitattributes.txt" "$TARGET/.gitattributes"
mv "$TARGET/editorconfig.txt" "$TARGET/.editorconfig"
mv "$TARGET/vscode" "$TARGET/.vscode"

tar -C "$TOOLKIT" --exclude=.git --exclude=template -cf - . | tar -C "$TARGET/libs/scene-toolkit" -xf -
git -C "$TARGET" init -q

echo "Hazır: $TARGET"
echo "Sonraki adım: cd $TARGET && ./run.sh editor"
