package scene.data;

import haxe.DynamicAccess;

typedef DataColumn = {
  var name : String;
  var title : String;
  var type : String;                       // DataTable.TEXT, NUMBER, ...
  @:optional var options : Array<String>;  // seçim sütunu
  @:optional var table : String;           // bağlantı sütunu
}

// Oyun verisi: fraksiyonlar, eşyalar gibi kayıtlar. Her tablo ayrı dosyadır ve her satır tek
// satıra yazılır: iki kişi farklı tablolarda çalışınca dosyaları çakışmaz.
class DataTable {
  public static inline var VERSION = 1;
  public static inline var SUFFIX = ".table.json";
  public static inline var TEXT = "metin";
  public static inline var NUMBER = "sayi";
  public static inline var INTEGER = "tam";
  public static inline var FLAG = "evet_hayir";
  public static inline var CHOICE = "secim";
  public static inline var REFERENCE = "baglanti";
  public static inline var COLOR = "renk";
  // res altındaki bir dosyanın yolu (model, doku): eşyanın modeli gibi.
  public static inline var ASSET = "varlik";
  public static var TYPES = [TEXT, NUMBER, INTEGER, FLAG, CHOICE, REFERENCE, COLOR, ASSET];

  public var name(default, null) : String;
  public var title : String;
  public var columns : Array<DataColumn> = [];
  public var rows : Array<DynamicAccess<Dynamic>> = [];

  public function new(name : String, title : String) {
    this.name = name;
    this.title = title;
  }

  public static function read(name : String, text : String) : DataTable {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw '$name tablosunun sürümü desteklenmiyor: ${raw.version}';
    var table = new DataTable(name, raw.title);
    table.columns = raw.columns;
    var rows : Array<DynamicAccess<Dynamic>> = raw.rows;
    table.rows = rows;
    return table;
  }

  public function write() : String {
    var out = new StringBuf();
    out.add('{\n  "version": $VERSION,\n  "title": ${quote(title)},\n  "columns": [');
    var lines = [for (column in columns) '\n    ${columnText(column)}'];
    out.add(lines.join(","));
    out.add(lines.length > 0 ? '\n  ],\n  "rows": [' : '],\n  "rows": [');
    var rowLines = [for (row in rows) '\n    ${rowText(row)}'];
    out.add(rowLines.join(","));
    out.add(rowLines.length > 0 ? '\n  ]\n}\n' : ']\n}\n');
    return out.toString();
  }

  public function clone() : DataTable {
    return read(name, write());
  }

  public function find(id : String) : Null<DynamicAccess<Dynamic>> {
    for (row in rows) if (row.get("id") == id) return row;
    return null;
  }

  public function ids() : Array<String> {
    return [for (row in rows) (row.get("id") : String)];
  }

  // Listede kimlikle birlikte görünen ad: ilk metin sütunu.
  public function label(id : String) : String {
    var row = find(id);
    if (row == null) return id;
    for (column in columns) if (column.type == TEXT && row.get(column.name) != null && row.get(column.name) != "") return '$id (${row.get(column.name)})';
    return id;
  }

  public function column(name : String) : Null<DataColumn> {
    for (item in columns) if (item.name == name) return item;
    return null;
  }

  public static function defaultValue(column : DataColumn) : Dynamic {
    return switch (column.type) {
      case NUMBER: 0.;
      case INTEGER, COLOR: 0;
      case FLAG: false;
      case CHOICE: column.options != null && column.options.length > 0 ? column.options[0] : "";
      default: "";
    };
  }

  // Yeni kimlik: ad tabanlı, çakışırsa numaralı.
  public function freeId(base : String) : String {
    var id = base, index = 2;
    while (find(id) != null) id = base + "_" + index++;
    return id;
  }

  public function addRow(id : String) {
    var row : DynamicAccess<Dynamic> = {};
    row.set("id", id);
    for (column in columns) row.set(column.name, defaultValue(column));
    rows.push(row);
    return row;
  }

  function columnText(column : DataColumn) {
    var parts = ['"name": ${quote(column.name)}', '"title": ${quote(column.title)}', '"type": ${quote(column.type)}'];
    if (column.options != null) parts.push('"options": ' + SceneFormat.writeValue(column.options));
    if (column.table != null) parts.push('"table": ${quote(column.table)}');
    return "{" + parts.join(", ") + "}";
  }

  function rowText(row : DynamicAccess<Dynamic>) {
    var parts = ['"id": ${quote(row.get("id"))}'];
    for (column in columns) parts.push('${quote(column.name)}: ${SceneFormat.writeValue(row.exists(column.name) ? row.get(column.name) : defaultValue(column))}');
    return "{" + parts.join(", ") + "}";
  }

  static function quote(text : String) {
    return haxe.Json.stringify(text);
  }
}
