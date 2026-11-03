package scene.save;

import scene.save.SaveFile.PackedSection;

// Kayıt dosyasının hücre bölümleri (hucre/<n>), önbellekli (docs/KAYIT_PLANI.md, Donmasız kayıt): yalnızca son
// kayıttan beri değişen hücreler (WorldDelta.touch) yeniden kodlanıp sıkıştırılır, ötekiler önbellekten gelir.
// Kayıt anının maliyeti dünyanın büyüklüğüne değil, değişen hücre sayısına bağlı kalır. Önbellek bir fark deposuna
// bağlıdır; depo değişince (kayıt yüklendi) baştan kurulur.
class DeltaSections {
  public static inline var PREFIX = "hucre/";
  public static inline var GLOBAL_KEY = "genel";

  var cache = new Map<Int, PackedSection>();
  var owner : Null<WorldDelta>;

  public function new() {}

  public static function nameOf(cell : Int) : String {
    return PREFIX + (cell == WorldDelta.GLOBAL ? GLOBAL_KEY : Std.string(cell));
  }

  public function sections(delta : WorldDelta) : Array<PackedSection> {
    var changed = delta.takeDirty();
    if (delta != owner) {
      owner = delta;
      cache = new Map();
      changed = delta.cellsWithData();
    }
    for (cell in changed) {
      var data = delta.cellData(cell);
      if (data == null) cache.remove(cell);
      else cache.set(cell, SaveFile.pack(nameOf(cell), haxe.io.Bytes.ofString(haxe.Json.stringify(data))));
    }
    var list = [for (section in cache) section];
    list.sort((a, b) -> a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    return list;
  }
}
