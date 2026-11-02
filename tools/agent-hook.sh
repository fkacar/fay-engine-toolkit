#!/bin/sh
# Claude Code PostToolUse hook'u: ajan res/ altına yazınca, editör açıksa ona ne olacağını söyler.
# Editör kapalıysa, dosya res/ dışındaysa veya bir şey okunamazsa hiçbir şey yazmadan çıkar:
# hata vermez, ajanı engellemez. Editör açıkken .editor/ajan-durum.json dosyasını iki saniyede bir yazar.
# Yalnızca sh, sed ve grep kullanır: macOS'ta ve Windows'taki Git Bash'te aynı çalışır.

ROOT=${CLAUDE_PROJECT_DIR:-.}
STATUS="$ROOT/.editor/ajan-durum.json"
FRESH_SECONDS=10

[ -f "$STATUS" ] || exit 0
INPUT=$(cat)

# Girdi JSON'undaki dosya yolu; Windows ters bölüleri düze çevrilir.
FILE=$(printf '%s' "$INPUT" | tr -d '\n' | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\\\/\//g')
case "$FILE" in
  res/*) RELATIVE=$FILE ;;
  */res/*) RELATIVE="res/${FILE##*/res/}" ;;
  *) exit 0 ;;
esac

NOW=$(date +%s)
WRITTEN=$(grep -o '"zaman"[[:space:]]*:[[:space:]]*[0-9]*' "$STATUS" | grep -o '[0-9]*$')
[ -n "$WRITTEN" ] || exit 0
[ $((NOW - WRITTEN)) -le $FRESH_SECONDS ] || exit 0

if grep -F "\"$RELATIVE\"" "$STATUS" > /dev/null; then
  NOTE="Editör açık ve $RELATIVE dosyasında tasarımcının kaydedilmemiş değişikliği var. Editör kaydederken birleştirecek; aynı nesneyi değiştirdiysen çakışma çıkar ve tasarımcı seçmek zorunda kalır. Mümkünse bu dosyaya dokunma."
else
  NOTE="Editör açık; $RELATIVE dosyasını bir saniye içinde yeniden yükleyecek. Tasarımcının bu dosyada kaydedilmemiş işi yok. Sonucu yoa-editor sunucusunun file_status aracıyla görebilirsin."
fi
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"yoa-editor: %s"}}\n' "$NOTE"
exit 0
