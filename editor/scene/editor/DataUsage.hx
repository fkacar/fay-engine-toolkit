package scene.editor;

import scene.data.DataTable;
import scene.data.Prefabs;
import scene.data.SceneData;
import scene.data.SceneFormat;
import sys.FileSystem;
import sys.io.File;

// Tablo satırının kullanıldığı yerler. Silinen veya kimliği değişen satır başka birinin sahnesini
// kırmasın diye Veri paneli önce buraya bakar. Açık sahne bellekten, diğerleri diskten okunur.
class DataUsage {
  static inline var LIMIT = 8;
  static var DIRECTORIES = ["res/scenes", "res/prefabs", "res/world"];

  public static function find(editor : Editor, table : String, id : String) : Array<String> {
    var fields = fieldsOf(editor.scene.registry, table);
    var found = [];
    for (entity in editor.scene.entities)
      for (component in entity.components) {
        var names = fields.get(component.componentId());
        if (names == null) continue;
        for (name in names) if (component.readField(name) == id) found.push('${entity.name} (${component.title()})');
      }
    for (path in files()) {
      if (editor.document.isOpenFile(path)) continue;
      var data = try SceneFormat.read(File.getContent(path)) catch (e : Dynamic) continue;
      for (entity in data.entities) if (uses(entity, fields, id)) found.push('${haxe.io.Path.withoutDirectory(path)}: ${entity.name}');
    }
    for (other in editor.data.tables)
      for (column in other.columns) {
        if (column.type != DataTable.REFERENCE || column.table != table) continue;
        for (row in other.rows) if (row.get(column.name) == id) found.push('${other.title} tablosu: ${row.get("id")}');
      }
    return found;
  }

  public static function describe(found : Array<String>) {
    var shown = found.slice(0, LIMIT).join(", ");
    return found.length > LIMIT ? '$shown ve ${found.length - LIMIT} yer daha' : shown;
  }

  static function uses(entity : EntityData, fields : Map<String, Array<String>>, id : String) {
    for (component in entity.components) {
      var names = fields.get(component.type);
      if (names != null) for (name in names) if (component.fields.get(name) == id) return true;
    }
    for (change in entity.overrides) {
      var parts = Prefabs.componentField(change.field);
      if (parts != null && fields.exists(parts.type) && fields.get(parts.type).indexOf(parts.name) >= 0 && change.value == id) return true;
    }
    return false;
  }

  // Tabloya bağlı alanlar, bileşen kimliğine göre.
  static function fieldsOf(registry : scene.ComponentRegistry, table : String) {
    var fields = new Map<String, Array<String>>();
    for (type in registry.currentTypes()) {
      var sample = registry.create(type);
      for (field in sample.describeFields())
        switch (field.hint) {
          case HRef(name) if (name == table):
            if (!fields.exists(type)) fields.set(type, []);
            fields.get(type).push(field.name);
          default:
        }
    }
    return fields;
  }

  static function files() : Array<String> {
    var found = [];
    for (directory in DIRECTORIES) {
      if (!FileSystem.exists(directory)) continue;
      for (name in FileSystem.readDirectory(directory))
        if (StringTools.endsWith(name, ".scene.json") || StringTools.endsWith(name, ".prefab.json")) found.push('$directory/$name');
    }
    return found;
  }
}
