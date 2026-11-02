package scene.data;

import haxe.DynamicAccess;

// Oyun tarafında tablolar adla, ilk istendiğinde okunur. Dosya `data/<ad>.table.json`.
class GameData {
  public static inline var DIRECTORY = "data";

  var read : String->Null<String>;
  var tables = new Map<String, Null<DataTable>>();

  public function new(read : String->Null<String>) {
    this.read = read;
  }

  public function table(name : String) : Null<DataTable> {
    if (tables.exists(name)) return tables.get(name);
    var text = read('$DIRECTORY/$name${DataTable.SUFFIX}');
    var table = text == null ? null : DataTable.read(name, text);
    tables.set(name, table);
    return table;
  }

  public function row(table : String, id : String) : Null<DynamicAccess<Dynamic>> {
    var data = this.table(table);
    return data == null ? null : data.find(id);
  }

  public function exists(table : String, id : String) {
    return row(table, id) != null;
  }
}
