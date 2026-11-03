package scene.editor;

import scene.Entity;
import scene.data.DataTable;
import scene.data.Prefabs;
import scene.data.SceneFormat;
import scene.editor.Validator.Issue;
import scene.editor.commands.SetTableCommand;
import scene.world.WorldData;

typedef ReleasedEntity = {id : String, name : String, types : Array<String>, cell : Int, position : Array<Float>};

// Kimlik güvenliği (docs/KAYIT_PLANI.md §8). Kayıt, oyuncunun ilerlemesini nesnenin kimliğine bağlar. Oyunculara
// ulaşmış durumlu nesnelerin listesi yayında yazılır (res/kayit/kimlikler.json). Listedeki bir nesne dünyadan
// kalkarsa oyuncu kayıtlarındaki durumu (çalışmış tetikleyici, NPC'ler) ona bağlanamaz: editör uyarır, yerine
// geçeni önerir; eşleme kayit_esleri tablosuna yazılır, oyun yüklerken farkı yeni kimliğe taşır.
// Liste yalnızca büyür: yeniden kaydetmek dünyadan kalkmış eski girdileri silmez, uyarıları ancak eşleme ya da
// bilerek bırakma kapatır. Eşlemeler zincirlenir (A→B, sonra B→C: A'nın durumu C'ye).
// Liste yoksa (henüz yayın yok) hiçbir şey denetlenmez.
class ReleaseIds {
  public static inline var PATH = "res/kayit/kimlikler.json";
  public static inline var TABLE = "kayit_esleri";
  public static inline var ABANDON = "birak";
  // Adı farklı olsa da bu kadar yakındaki aynı türden nesne yerine geçen sayılır.
  static inline var NEAR = 10.;

  var editor : Editor;
  var cached : Null<Array<ReleasedEntity>>;
  var cachedTime = -1.;
  var saveableTypes = new Map<String, Bool>();

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function list() : Array<ReleasedEntity> {
    if (!sys.FileSystem.exists(PATH)) return [];
    var time = sys.FileSystem.stat(PATH).mtime.getTime();
    if (cached == null || time != cachedTime) {
      var raw : Dynamic = try haxe.Json.parse(sys.io.File.getContent(PATH)) catch (e : Dynamic) null;
      cached = raw == null || raw.entities == null ? [] : raw.entities;
      cachedTime = time;
    }
    return cached;
  }

  // Eski kimlik → yeni kimlik; tablo satırının kimliği eski kimliktir.
  public function mappings() : Map<String, String> {
    var result = new Map<String, String>();
    var table = editor.data.tables.get(TABLE);
    if (table != null)
      for (row in table.rows) {
        var to : Null<String> = row.get("yeni");
        if (to != null && to != "") result.set(row.get("id"), to);
      }
    return result;
  }

  // Tasarımcının bilerek kaldırdığı yayın nesneleri: oyuncu kayıtlarındaki durumları bağlanmadan kalır.
  public function abandoned() : Map<String, Bool> {
    var result = new Map<String, Bool>();
    var table = editor.data.tables.get(TABLE);
    if (table != null) for (row in table.rows) if (row.get(ABANDON) == true) result.set(row.get("id"), true);
    return result;
  }

  // Zincirin sonu: A→B, B→C ise A'nın yeni kimliği C.
  public static function resolve(id : String, pairs : Map<String, String>) : String {
    var at = id, seen = new Map<String, Bool>();
    while (pairs.exists(at) && !seen.exists(at)) {
      seen.set(at, true);
      at = pairs.get(at);
    }
    return at;
  }

  // Yayın: dünyadaki bütün durumlu nesneler dosyaya; önceki yayınlarda olup dünyadan kalkmış olanlar listede kalır.
  // Dosya işidir, geri alınmaz; depoya girer. Dönen unresolved: dünyada olmayıp eşlenmemiş ve bırakılmamışlar.
  public function record() : {count : Int, unresolved : Array<ReleasedEntity>} {
    var items = current();
    var present = [for (item in items) item.id => true];
    for (old in list()) if (!present.exists(old.id)) items.push(old);
    items.sort((a, b) -> a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    if (!sys.FileSystem.exists("res/kayit")) sys.FileSystem.createDirectory("res/kayit");
    var lines = [for (item in items) '    ${haxe.Json.stringify(item)}'];
    sys.io.File.saveContent(PATH, '{\n  "version": 1,\n  "date": ${haxe.Json.stringify(DateTools.format(Date.now(), "%Y-%m-%d %H:%M"))},\n  "entities": [\n${lines.join(",\n")}\n  ]\n}\n');
    cached = null;
    return {count: items.length, unresolved: [for (item in missing()) item.released]};
  }

  // Dünyadaki durumlu (Saveable) nesneler: yüklü hücreler editörden (kaydedilmemiş değişiklikler dahil),
  // yüklü olmayanlar diskten, prefab içleri açılmış.
  public function current() : Array<ReleasedEntity> {
    var world = editor.document.world;
    var found : Array<ReleasedEntity> = [];
    for (entity in editor.scene.entities) {
      var types = [for (component in entity.components) if (Std.isOfType(component, scene.save.Saveable)) component.componentId()];
      if (types.length == 0) continue;
      var root = entity;
      while (root.parent != null) root = root.parent;
      var at = entity.object.getAbsPos();
      found.push({id: entity.id, name: entity.name, types: types, cell: world == null ? WorldData.GLOBAL : world.cellOf(root),
        position: [round(at.tx), round(at.ty), round(at.tz)]});
    }
    if (world == null) return found;
    for (cell in world.data.cells()) {
      if (world.isLoaded(cell)) continue;
      var path = "res/" + world.data.path(cell, WorldData.OBJECTS_SUFFIX);
      if (!sys.FileSystem.exists(path)) continue;
      var data = try SceneFormat.read(sys.io.File.getContent(path)) catch (e : Dynamic) null;
      if (data == null) continue;
      for (item in data.entities) {
        var expanded = item.prefab == null ? [item] : try [for (part in Prefabs.expand(item, editor.scene.prefabData, _ -> {})) part.data] catch (e : Dynamic) [item];
        for (part in expanded) {
          var types = [for (component in part.components) if (isSaveable(component.type)) component.type];
          if (types.length > 0) found.push({id: part.id, name: part.name, types: types, cell: cell, position: part.position.copy()});
        }
      }
    }
    return found;
  }

  // Yayında olup dünyada olmayanlar (eşlenip yenisi duranlar hariç) ve her biri için yerine geçen önerisi.
  public function missing() : Array<{released : ReleasedEntity, successor : Null<ReleasedEntity>}> {
    var released = list();
    if (released.length == 0) return [];
    var now = current();
    var present = [for (item in now) item.id => item];
    var mapped = mappings(), dropped = abandoned();
    var releasedIds = [for (item in released) item.id => true];
    var taken = [for (to in mapped) to => true];
    var result = [];
    for (old in released) {
      if (present.exists(old.id) || dropped.exists(old.id)) continue;
      // Eşlenmişse zincirin sonuna bakılır: dünyadaysa sorun yok; sonu da yayında bir nesneyse uyarı onun için çıkar.
      if (mapped.exists(old.id)) {
        var end = resolve(old.id, mapped);
        if (present.exists(end) || (end != old.id && releasedIds.exists(end))) continue;
      }
      var best : Null<ReleasedEntity> = null, bestScore = Math.POSITIVE_INFINITY;
      for (item in now) {
        if (releasedIds.exists(item.id) || taken.exists(item.id)) continue;
        if (!Lambda.exists(item.types, type -> old.types.indexOf(type) >= 0)) continue;
        var distance = old.cell == item.cell || old.cell == WorldData.GLOBAL ? Math.sqrt(Math.pow(item.position[0] - old.position[0], 2) + Math.pow(item.position[1] - old.position[1], 2)) : Math.POSITIVE_INFINITY;
        // Aynı ad en güçlü işaret; adı farklıysa yalnızca yakındaki.
        var score = item.name == old.name ? Math.min(distance, 1e6) * 1e-6 : distance <= NEAR ? 1 + distance : Math.POSITIVE_INFINITY;
        if (score < bestScore) {
          bestScore = score;
          best = item;
        }
      }
      result.push({released: old, successor: best});
    }
    return result;
  }

  public function issues() : Array<Issue> {
    return [for (item in missing()) {
      var old = item.released, next = item.successor;
      var message = 'Yayındaki "${old.name}" (${old.types.join(", ")}) dünyada yok: oyuncu kayıtlarındaki durumu kaybolur.'
        + (next != null ? ' Yerine geçen "${next.name}" ise Eşle.' : ' Geri al ya da yerine geçeni yapıp eşle.')
        + ' Bilerek kaldırdıysan Bırak.';
      var issue : Issue = {entity: next == null ? null : editor.scene.find(next.id), message: message, actions: []};
      if (next != null) issue.actions.push({label: "Eşle", run: () -> map(old.id, next.id, old.name)});
      issue.actions.push({label: "Bırak", run: () -> abandon(old.id, old.name)});
      issue;
    }];
  }

  // Yayındaki ve eşlenmemiş nesneler (silerken onay için): ad listesi, alt nesneler dahil.
  public function protectedNames(roots : Array<Entity>) : Array<String> {
    var released = list();
    if (released.length == 0) return [];
    var ids = [for (item in released) item.id => item.name];
    var mapped = mappings();
    var names = [];
    function visit(entity : Entity) {
      if (ids.exists(entity.id) && !mapped.exists(entity.id)) names.push(entity.name);
      for (child in entity.children) visit(child);
    }
    for (root in roots) visit(root);
    return names;
  }

  // Eşleme tek geri alma adımıdır; tablo yoksa açılır.
  public function map(from : String, to : String, name : String) {
    write(from, to, false, name, 'Eşle: $name');
    editor.show('Eşlendi: "$name" oyuncu kayıtlarında yeni nesneye geçecek');
  }

  // Bilerek kaldırıldı: uyarı kapanır, durum oyuncu kayıtlarında bağsız kalır (zararsız); sonra eşlenirse yine geçer.
  public function abandon(from : String, name : String) {
    write(from, "", true, name, 'Bırak: $name');
    editor.show('Bırakıldı: "$name" oyuncu kayıtlarında hiçbir nesneye bağlanmayacak');
  }

  function write(from : String, to : String, drop : Bool, name : String, label : String) {
    var before = editor.data.text(TABLE);
    var table = before == null ? new DataTable(TABLE, "Kayıt eşlemeleri") : DataTable.read(TABLE, before);
    for (column in [
      {name: "yeni", title: "Yeni kimlik", type: DataTable.TEXT},
      {name: "ad", title: "Ad", type: DataTable.TEXT},
      {name: ABANDON, title: "Bırakıldı", type: DataTable.FLAG},
    ]) if (!Lambda.exists(table.columns, c -> c.name == column.name)) table.columns.push(column);
    var row = table.find(from);
    if (row == null) row = table.addRow(from);
    row.set("yeni", to);
    row.set("ad", name);
    row.set(ABANDON, drop);
    editor.commands.execute(new SetTableCommand(label, editor.data, TABLE, before, table.write()));
    editor.document.validate();
  }

  function isSaveable(type : String) : Bool {
    if (!saveableTypes.exists(type)) {
      var component = editor.scene.registry.create(type);
      saveableTypes.set(type, component != null && Std.isOfType(component, scene.save.Saveable));
    }
    return saveableTypes.get(type);
  }

  static function round(value : Float) : Float {
    return Math.round(value * 100) / 100;
  }
}
