package scene.data;

import haxe.DynamicAccess;

typedef TranslationAudit = {
  // Kaynakta dolu olup çeviride olmayan ya da boş hücreler: "satır.sütun".
  var missing : Array<String>;
  // Çevrildiği kaynak metin değişmiş hücreler (özet tutmuyor).
  var stale : Array<String>;
  // Kaynakta olmayan satırlar ("satır") ya da çevrilir olmayan sütunlar (".sütun").
  var extra : Array<String>;
}

// Çeviri katmanı: bir tablonun çevrilir sütunlarının (DataColumn.translatable) dil başına çevirisi
// `ceviri/<dil>/<tablo>.table.json` dosyasındadır. Satır kimlikleri kaynak tabloyla aynıdır; her çevrilir sütunun yanında
// `<sütun>_kaynak` sütunu çevrilen kaynak metnin özetini tutar: kaynak değişince çeviri eskimiş sayılır.
// Dil listesini, kaynak dili ve yedek sırasını oyun bilir; bu sınıf yalnızca dosyaları okur, yazar ve karşılaştırır.
class Translations {
  public static inline var DIRECTORY = "ceviri";
  public static inline var SOURCE_SUFFIX = "_kaynak";

  var read : String->Null<String>;
  var tables = new Map<String, Null<DataTable>>();

  public function new(read : String->Null<String>) {
    this.read = read;
  }

  public static function path(language : String, table : String) : String {
    return '$DIRECTORY/$language/$table${DataTable.SUFFIX}';
  }

  public function table(language : String, name : String) : Null<DataTable> {
    var key = '$language/$name';
    if (tables.exists(key)) return tables.get(key);
    var text = read(path(language, name));
    var table = text == null ? null : DataTable.read(name, text);
    tables.set(key, table);
    return table;
  }

  // Çeviri dosyası değişince bir sonraki okuma yeniden ayrıştırır. Dil ya da ad yoksa hepsi.
  public function forget(?language : String, ?name : String) {
    if (language == null && name == null) {
      tables.clear();
      return;
    }
    for (key in [for (key in tables.keys()) key]) {
      var parts = key.split("/");
      if ((language == null || parts[0] == language) && (name == null || parts[1] == name)) tables.remove(key);
    }
  }

  // Çeviri hücresi; dosya, satır ya da hücre yoksa ya da boşsa null (oyun kaynağa düşer).
  public function text(language : String, table : String, id : String, column : String) : Null<String> {
    var data = this.table(language, table);
    var row = data == null ? null : data.find(id);
    var value : Null<String> = row == null ? null : row.get(column);
    return value == null || value == "" ? null : value;
  }

  // Kaynak metnin özeti: UTF-8 baytlarının MD5'inin ilk 8 onaltılık hanesi (araçlar da aynısını üretir).
  public static function digest(text : String) : String {
    return haxe.crypto.Md5.make(haxe.io.Bytes.ofString(text)).toHex().substr(0, 8);
  }

  // Bir dilin bir kaynak tablo için durumu (oyunla gelen dilde eksik ve eskimiş hatadır, sonradan eklenen dilde sayılır).
  public function audit(language : String, source : DataTable) : TranslationAudit {
    var missing : Array<String> = [], stale : Array<String> = [], extra : Array<String> = [];
    var columns = source.translatableColumns();
    var data = table(language, source.name);
    for (row in source.rows) {
      var id : String = row.get("id");
      var cell = data == null ? null : data.find(id);
      for (column in columns) {
        var original : Null<String> = row.get(column);
        if (original == null || original == "") continue;
        var value : Null<String> = cell == null ? null : cell.get(column);
        if (value == null || value == "") missing.push('$id.$column');
        else if (cell.get(column + SOURCE_SUFFIX) != digest(original)) stale.push('$id.$column');
      }
    }
    if (data != null) {
      for (row in data.rows) if (source.find(row.get("id")) == null) extra.push(Std.string(row.get("id")));
      for (column in data.columns)
        if (!StringTools.endsWith(column.name, SOURCE_SUFFIX) && columns.indexOf(column.name) < 0) extra.push('.${column.name}');
    }
    return {missing: missing, stale: stale, extra: extra};
  }

  // Bir çeviri hücresini yazar (editör ve ajan): çeviri tablosu yoksa kaynağın çevrilir sütunlarıyla kurulur, özet kaynağın
  // bugünkü metninden alınır. Kaynakta olmayan satır ya da çevrilir olmayan sütun yazılmaz (false).
  public static function put(translation : Null<DataTable>, source : DataTable, id : String, column : String, value : String) : {table : DataTable, ok : Bool} {
    var table = translation != null ? translation : empty(source);
    var original = source.find(id);
    if (original == null || source.translatableColumns().indexOf(column) < 0) return {table: table, ok: false};
    for (name in [column, column + SOURCE_SUFFIX]) if (table.column(name) == null) {
      var info = source.column(column);
      table.columns.push(name == column ? {name: name, title: info.title, type: DataTable.TEXT, translatable: true}
        : {name: name, title: info.title + " (kaynak özeti)", type: DataTable.TEXT});
    }
    var row : DynamicAccess<Dynamic> = table.find(id);
    if (row == null) row = table.addRow(id);
    row.set(column, value);
    var text : Null<String> = original.get(column);
    row.set(column + SOURCE_SUFFIX, digest(text == null ? "" : text));
    return {table: table, ok: true};
  }

  static function empty(source : DataTable) : DataTable {
    return new DataTable(source.name, source.title);
  }
}
