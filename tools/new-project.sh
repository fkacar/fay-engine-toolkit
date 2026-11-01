#!/bin/sh
# Şablondan yeni oyun projesi oluşturur. Windows'ta Git Bash ile çalışır.
# Kullanım: sh libs/scene-toolkit/tools/new-project.sh ../yeni-oyun
set -e

if [ $# -ne 1 ]; then
  echo "Kullanım: new-project.sh <hedef klasör>" >&2
  exit 1
fi

TOOLKIT_URL=https://github.com/fkacar/fay-engine-toolkit.git
TOOLKIT=$(cd "$(dirname "$0")/.." && pwd)
COMMIT=$(git -C "$TOOLKIT" rev-parse HEAD)
TARGET=$1

if [ -e "$TARGET" ]; then
  echo "Hedef zaten var: $TARGET" >&2
  exit 1
fi

mkdir -p "$TARGET"
cp -R "$TOOLKIT/template/." "$TARGET/"
mv "$TARGET/gitignore.txt" "$TARGET/.gitignore"
mv "$TARGET/gitattributes.txt" "$TARGET/.gitattributes"
mv "$TARGET/editorconfig.txt" "$TARGET/.editorconfig"
mv "$TARGET/vscode" "$TARGET/.vscode"

git -C "$TARGET" init -q
git -C "$TARGET" submodule --quiet add "$TOOLKIT_URL" libs/scene-toolkit
git -C "$TARGET/libs/scene-toolkit" checkout -q "$COMMIT"
git -C "$TARGET" submodule --quiet update --init --recursive
git -C "$TARGET" add libs/scene-toolkit

echo "Hazır: $TARGET"
echo "Sonraki adım: cd $TARGET && ./run.sh editor"
