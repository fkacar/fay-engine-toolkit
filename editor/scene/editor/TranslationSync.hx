package scene.editor;

import scene.data.DataTable;
import scene.data.Translations;
import scene.editor.commands.SetTableCommand;

// Kaynak tablo değişince çevirileri uyar (Data paneli ve ajanın edit_table aracı aynı yoldan): kaynakta silinen satır ve
// sütun, çevrilir olmaktan çıkan sütun çeviriden de silinir; kimliği değişen satırın çevirisi yeni kimliğe geçer. Dönen
// komutlar kaynak tablonun komutuyla tek geri alma adımında yürür. Kaynak metin değişince çeviri silinmez, eskimiş sayılır.
class TranslationSync {
  public static function commands(editor : Editor, name : String, after : DataTable, ?renamed : Map<String, String>) : Array<Command> {
    var list : Array<Command> = [];
    var keep = after.translatableColumns();
    for (key => layer in editor.translations.tables) {
      var slash = key.indexOf("/");
      if (slash < 0 || key.substr(slash + 1) != name) continue;
      var copy = layer.clone();
      if (renamed != null) for (old => fresh in renamed) {
        var row = copy.find(old);
        if (row != null) row.set("id", fresh);
      }
      copy.rows = copy.rows.filter(row -> after.find(row.get("id")) != null);
      copy.columns = copy.columns.filter(column -> {
        var base = StringTools.endsWith(column.name, Translations.SOURCE_SUFFIX)
          ? column.name.substr(0, column.name.length - Translations.SOURCE_SUFFIX.length) : column.name;
        keep.indexOf(base) >= 0;
      });
      for (row in copy.rows) for (field in [for (field in row.keys()) field]) if (field != "id" && copy.column(field) == null) row.remove(field);
      var before = layer.write(), text = copy.write();
      if (text != before) list.push(new SetTableCommand("Çeviri", editor.translations, key, before, text));
    }
    return list;
  }
}
