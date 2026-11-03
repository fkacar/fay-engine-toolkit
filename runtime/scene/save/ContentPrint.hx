package scene.save;

import haxe.DynamicAccess;
import scene.world.WorldData;

// İçerik izi: dünyanın nesne dosyalarının (hücre hücre) ve veri tablolarının özeti (CRC32). Kayda yazılır;
// yüklerken kayıttan sonra değişen hücreler ve tablolar bilinir. Kayıttan hata ayıklamada hatanın bugünkü
// dünyada da olup olmadığını ayırmaya yarar.
typedef ContentPrintData = {cells : DynamicAccess<Int>, tables : DynamicAccess<Int>};

class ContentPrint {
  public static inline var GLOBAL_KEY = "genel";

  // tables: tablo adları (data/<ad>.table.json); read: res köküne göre dosya okur.
  public static function compute(world : Null<WorldData>, tables : Array<String>, read : String->Null<String>) : ContentPrintData {
    var cells : DynamicAccess<Int> = {}, sums : DynamicAccess<Int> = {};
    if (world != null)
      for (cell in [WorldData.GLOBAL].concat(world.cells())) {
        var text = read(world.path(cell, WorldData.OBJECTS_SUFFIX));
        if (text != null) cells.set(keyOf(cell), sum(text));
      }
    var names = tables.copy();
    names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    for (name in names) {
      var text = read('${scene.data.GameData.DIRECTORY}/$name${scene.data.DataTable.SUFFIX}');
      if (text != null) sums.set(name, sum(text));
    }
    return {cells: cells, tables: sums};
  }

  // Kayıttan sonra değişen, eklenen ya da silinen hücreler ve tablolar. Kayıtta iz yoksa (eski kayıt) null.
  public static function diff(saved : Null<Dynamic>, now : ContentPrintData) : Null<{cells : Array<String>, tables : Array<String>}> {
    if (saved == null || saved.cells == null || saved.tables == null) return null;
    return {cells: changed(saved.cells, now.cells), tables: changed(saved.tables, now.tables)};
  }

  public static function keyOf(cell : Int) : String {
    return cell == WorldData.GLOBAL ? GLOBAL_KEY : Std.string(cell);
  }

  static function changed(before : DynamicAccess<Int>, after : DynamicAccess<Int>) : Array<String> {
    var keys = [for (key in before.keys()) if (!after.exists(key) || after.get(key) != before.get(key)) key];
    for (key in after.keys()) if (!before.exists(key)) keys.push(key);
    keys.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return keys;
  }

  static function sum(text : String) : Int {
    return haxe.crypto.Crc32.make(haxe.io.Bytes.ofString(text));
  }
}
