package scene.editor;

import scene.data.DataTable;
import scene.data.Translations;
import scene.story.Dialog;

// Bir dilin bir tablodaki (ya da diyalogdaki) çeviri durumu. Anahtarlar "<satır>.<sütun>" (diyalogda satır düğüm ya da
// düğüm.seçenek, sütun metin).
typedef TranslationReport = {
  language : String,
  table : String,
  title : String,
  missing : Array<String>,
  stale : Array<String>,
  extra : Array<String>,
};

// Çevirilerin durumu (docs/DIL_PLANI.md, D8): editörün bellekteki tabloları, diyalogları ve çevirileri (kaydedilmemiş
// değişiklikler dahil). Çeviriler paneli, ajanın list_translations aracı ve sınavın çeviri kontrolü aynı yoldan okur.
class TranslationStatus {
  // Kaynak dil dışındaki diller (oyun dil bildirmiyorsa boş).
  public static function others(editor : Editor) : Array<String> {
    return [for (code in editor.languages) if (code != editor.sourceLanguage) code];
  }

  // Çevrilir kaynaklar: çevrilir sütunu olan tablolar ve diyaloglar ("diyaloglar/<id>", Dialog.texts).
  public static function sources(editor : Editor) : Array<String> {
    var names = [for (name in editor.data.names()) if (editor.data.tables.get(name).translatableColumns().length > 0) name];
    for (id in editor.dialogs.ids()) names.push(Dialog.textTableName(id));
    return names;
  }

  public static function source(editor : Editor, name : String) : Null<DataTable> {
    if (StringTools.startsWith(name, Dialog.TEXT_TABLE_PREFIX)) {
      var dialog = editor.dialogs.dialogs.get(name.substr(Dialog.TEXT_TABLE_PREFIX.length));
      return dialog == null ? null : dialog.texts();
    }
    return editor.data.tables.get(name);
  }

  // Editörün bellekteki çevirilerini okuyan çeviri katmanı (diskteki değil).
  public static function reader(editor : Editor) : Translations {
    return new Translations(path -> {
      var prefix = Translations.DIRECTORY + "/";
      editor.translations.text(path.substring(prefix.length, path.length - DataTable.SUFFIX.length));
    });
  }

  // Dil ve kaynak başına durum. languages verilmezse kaynak dışındaki bütün diller, names verilmezse bütün kaynaklar.
  public static function report(editor : Editor, ?languages : Array<String>, ?names : Array<String>) : Array<TranslationReport> {
    var codes = languages != null ? languages : others(editor);
    var list = names != null ? names : sources(editor);
    var layer = reader(editor), found = [];
    for (name in list) {
      var table = source(editor, name);
      if (table == null || table.translatableColumns().length == 0) continue;
      for (language in codes) {
        var audit = layer.audit(language, table);
        found.push({language: language, table: name, title: table.title == null || table.title == "" ? name : table.title,
          missing: audit.missing, stale: audit.stale, extra: audit.extra});
      }
    }
    return found;
  }

  // "<satır>.<sütun>" anahtarını ayırır: sütun son noktadan sonrası (diyalog seçeneğinin satırı "3.1" noktalıdır).
  public static function split(key : String) : {row : String, column : String} {
    var dot = key.lastIndexOf(".");
    return dot < 0 ? {row: key, column: ""} : {row: key.substr(0, dot), column: key.substr(dot + 1)};
  }
}
