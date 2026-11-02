#!/bin/sh
# Toolkit ve oyun reposunu doğru sırayla gönderir: önce toolkit, sonra onun commit'ini gösteren
# oyun commit'i. Sıra terse dönerse oyun eski toolkit'e bağlı kalır ve temiz klon derlenmez.
#
#   ./push.sh "commit mesajı"              Kontrol eder, listeyi gösterir, onayla gönderir
#   ./push.sh --dry-run "commit mesajı"    Yalnızca kontrol eder, hiçbir şeyi değiştirmez
#   ./push.sh --yes "commit mesajı"        Onay sormaz
#   ./push.sh --no-build "commit mesajı"   Derleme ve test kontrolünü atlar
#
# Başkasının gönderdiği toolkit commit'i de aynı komutla oyuna kaydedilir.
# Yarıda kalırsa sorun çözülüp aynı komut yeniden çalıştırılır.
set -eu
cd "$(dirname "$0")/../../.."

TOOLKIT=libs/scene-toolkit
BRANCH=main
CHECKS="build.hxml editor.hxml build-mac.hxml editor-mac.hxml $TOOLKIT/tests.hxml"

DRY_RUN=0
ASSUME_YES=0
BUILD=1
MESSAGE=""
STAGE=check

toolkit() {
  git -C "$TOOLKIT" "$@"
}

stop() {
  printf '\nDURDU: %s\n' "$1" >&2
  exit 1
}

report() {
  [ "$1" = 0 ] && return
  case "$STAGE" in
    check) echo "Hiçbir şey commit edilmedi, gönderilmedi." >&2 ;;
    toolkit) echo "Oyun reposuna dokunulmadı. Sorunu çözüp aynı komutu yeniden çalıştır." >&2 ;;
    game) echo "Toolkit GitHub'da, oyun reposu gönderilmedi. Sorunu çözüp aynı komutu yeniden çalıştır." >&2 ;;
  esac
}
trap 'report $?' EXIT

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    --no-build) BUILD=0 ;;
    -*) stop "bilinmeyen seçenek: $arg" ;;
    *) MESSAGE=$arg ;;
  esac
done
[ -n "$MESSAGE" ] || stop 'commit mesajı gerekli: ./push.sh "mesaj"'

[ -f "$TOOLKIT/runtime.hxml" ] || stop "$TOOLKIT boş. Önce git submodule update --init --recursive çalıştır."
[ "$(git symbolic-ref -q --short HEAD || true)" = "$BRANCH" ] || stop "oyun reposu $BRANCH dalında değil."

# Submodule pull sonrası bir dalda değil belirli bir commit'te durur, commit oraya atılırsa kaybolur.
TOOLKIT_BRANCH=$(toolkit symbolic-ref -q --short HEAD || true)
if [ -z "$TOOLKIT_BRANCH" ]; then
  toolkit merge-base --is-ancestor HEAD "$BRANCH" ||
    stop "toolkit, $BRANCH dalında olmayan bir commit'te. git -C $TOOLKIT log -1 ile bak."
  if [ "$DRY_RUN" = 1 ]; then
    echo "Toolkit $BRANCH dalına alınacak."
  else
    toolkit switch -q "$BRANCH" || stop "toolkit $BRANCH dalına alınamadı, commit'siz değişiklik çakışıyor."
  fi
elif [ "$TOOLKIT_BRANCH" != "$BRANCH" ]; then
  stop "toolkit $TOOLKIT_BRANCH dalında, $BRANCH bekleniyordu."
fi

git fetch -q --no-recurse-submodules origin "$BRANCH"
toolkit fetch -q origin "$BRANCH"

GAME_BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH")
[ "$GAME_BEHIND" = 0 ] || stop "oyun reposu $GAME_BEHIND commit geride. Önce git pull --no-recurse-submodules çalıştır."

TOOLKIT_BEHIND=$(toolkit rev-list --count "HEAD..origin/$BRANCH")
TOOLKIT_AHEAD=$(toolkit rev-list --count "origin/$BRANCH..HEAD")
TOOLKIT_CHANGES=$(toolkit status --porcelain)

if toolkit submodule status | grep -q '^+'; then
  stop "hlimgui sabit sürümünde değil. git -C $TOOLKIT submodule update --init --recursive çalıştır."
fi

# Başkasının toolkit commit'i: yerelde iş yoksa alınır, varsa üzerine yazılmaz.
if [ "$TOOLKIT_BEHIND" != 0 ]; then
  [ "$TOOLKIT_AHEAD" = 0 ] && [ -z "$TOOLKIT_CHANGES" ] ||
    stop "toolkit'te GitHub'da yeni commit var ve sende de değişiklik var. git -C $TOOLKIT pull --rebase --autostash origin $BRANCH çalıştır."
  if [ "$DRY_RUN" = 1 ]; then
    echo "Toolkit'in yeni commit'leri alınacak: $TOOLKIT_BEHIND"
  else
    toolkit merge -q --ff-only "origin/$BRANCH"
    toolkit submodule update -q --init --recursive
    TOOLKIT_BEHIND=0
  fi
fi

# Eksik satır, diyalog veya prefab derlemeyi durdurmaz (ekip editörü açıp düzeltebilsin diye),
# yalnızca uyarı verir. Gönderen kişi onaydan önce bunları görür.
CONTENT_WARNINGS=""
if [ "$BUILD" = 1 ] && [ "$TOOLKIT_BEHIND" = 0 ]; then
  echo "Derleme ve testler kontrol ediliyor..."
  LOG=$(mktemp)
  for hxml in $CHECKS; do
    haxe "$hxml" > "$LOG" 2>&1 || {
      tail -15 "$LOG" >&2
      stop "$hxml geçmedi."
    }
    FOUND=$(grep -E '\.(scene|prefab)\.json:[0-9]+: .*Warning : ' "$LOG" | sed 's/.*Warning : //')
    [ -z "$FOUND" ] || CONTENT_WARNINGS=$(printf '%s\n%s' "$CONTENT_WARNINGS" "$FOUND" | sed '/^$/d' | sort -u)
  done
fi

GAME_CHANGES=$(git status --porcelain)
GAME_AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD")
if [ -z "$TOOLKIT_CHANGES" ] && [ "$TOOLKIT_AHEAD" = 0 ] && [ -z "$GAME_CHANGES" ] && [ "$GAME_AHEAD" = 0 ]; then
  echo "Gönderilecek bir şey yok."
  exit 0
fi

echo
echo "Mesaj: $MESSAGE"
if [ -n "$TOOLKIT_CHANGES" ]; then
  echo "Toolkit:"
  toolkit status --short
fi
[ "$TOOLKIT_AHEAD" = 0 ] || echo "Toolkit'te gönderilmemiş commit: $TOOLKIT_AHEAD"
if [ -n "$GAME_CHANGES" ]; then
  echo "Oyun:"
  git status --short
fi
[ "$GAME_AHEAD" = 0 ] || echo "Oyunda gönderilmemiş commit: $GAME_AHEAD"
if [ -n "$CONTENT_WARNINGS" ]; then
  echo
  echo "Uyarı: sahnelerde eksik içerik var. Oyun açılır ama bu nesneler eksik kalır, editörde Uyarılar panelinde görünür:"
  printf '%s\n' "$CONTENT_WARNINGS" | sed 's/^/  /'
fi
echo

if [ "$DRY_RUN" = 1 ]; then
  echo "Kuru çalışma: hiçbir şey değiştirilmedi."
  exit 0
fi

if [ "$ASSUME_YES" = 0 ]; then
  [ -t 0 ] || stop "onay için terminalde çalıştır ya da --yes ekle."
  printf 'Gönderilsin mi? [e/H] '
  read -r ANSWER || ANSWER=""
  case "$ANSWER" in
    e|E|evet) ;;
    *)
      echo "Vazgeçildi."
      exit 0
      ;;
  esac
fi

STAGE=toolkit
if [ -n "$TOOLKIT_CHANGES" ]; then
  toolkit add -A
  toolkit commit -q -m "$MESSAGE"
fi
if [ "$(toolkit rev-list --count "origin/$BRANCH..HEAD")" != 0 ]; then
  toolkit push -q origin "$BRANCH"
fi
TOOLKIT_HEAD=$(toolkit rev-parse HEAD)
[ "$(toolkit ls-remote origin "refs/heads/$BRANCH" | cut -f1)" = "$TOOLKIT_HEAD" ] ||
  stop "toolkit GitHub'a ulaşmadı."

STAGE=game
git add -A
git diff --cached --quiet || git commit -q -m "$MESSAGE"
[ "$(git rev-parse "HEAD:$TOOLKIT")" = "$TOOLKIT_HEAD" ] ||
  stop "oyun commit'i toolkit'in son commit'ini göstermiyor."
git push -q origin "$BRANCH"
[ "$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)" = "$(git rev-parse HEAD)" ] ||
  stop "oyun reposu GitHub'a ulaşmadı."

echo "Tamam: toolkit $(toolkit rev-parse --short HEAD), oyun $(git rev-parse --short HEAD)"
