package scene.editor;

import scene.FieldInfo.FieldHint;
import scene.data.DataTable;
import scene.data.Prefabs;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.story.Dialog;
import sys.FileSystem;
import sys.io.File;

// Tablo satırının ve diyaloğun kullanıldığı yerler. Silinen veya kimliği değişen satır başka birinin
// sahnesini kırmasın diye Veri ve Diyaloglar paneli önce buraya bakar. Açık sahne bellekten,
// diğerleri diskten okunur.
class DataUsage {
  static inline var LIMIT = 8;
  static inline var CACHE_SECONDS = 2.;
  static var DIRECTORIES = ["res/scenes", "res/prefabs", "res/world"];

  static var startersCache : Map<String, Array<String>> = [];
  static var cacheRevision = -1;
  static var cacheTime = 0.;

  public static function find(editor : Editor, table : String, id : String) : Array<String> {
    var found = scan(editor, fieldsOf(editor.scene.registry, hint -> switch (hint) {
      case HRef(name): name == table;
      default: false;
    }), id);
    for (other in editor.data.tables)
      for (column in other.columns) {
        if (column.type != DataTable.REFERENCE || column.table != table) continue;
        for (row in other.rows) if (row.get(column.name) == id) found.push('${other.title} tablosu: ${row.get("id")}');
      }
    // Diyaloğun eşya koşulu da satırı kullanır.
    if (table == editor.dialogs.itemTable)
      for (key in editor.dialogs.ids()) {
        var dialog = editor.dialogs.dialogs.get(key);
        if (Lambda.exists(dialog.nodes, node -> node.type == Dialog.CONDITION && node.kind == Dialog.ITEM && node.name == id))
          found.push('Diyalog ${dialog.title}');
      }
    // Diyaloğun satırı konuşanın satırını kullanır.
    if (table == editor.dialogs.speakerTable)
      for (key in editor.dialogs.ids()) {
        var dialog = editor.dialogs.dialogs.get(key);
        if (Lambda.exists(dialog.nodes, node -> node.type == Dialog.LINE && node.speaker == id)) found.push('Diyalog ${dialog.title}');
      }
    // Diyaloğun İlişki koşulu fraksiyonun satırını kullanır.
    if (table == editor.dialogs.factionTable)
      for (key in editor.dialogs.ids()) {
        var dialog = editor.dialogs.dialogs.get(key);
        if (Lambda.exists(dialog.nodes, node -> node.type == Dialog.CONDITION && node.kind == Dialog.STANDING && node.name == id))
          found.push('Diyalog ${dialog.title}');
      }
    return found;
  }

  public static function findDialog(editor : Editor, id : String) : Array<String> {
    return scan(editor, dialogFields(editor), id);
  }

  // Liste ve Inspector her karede sorar: diskteki dosyalar en çok iki saniyede bir okunur.
  public static function dialogStarters(editor : Editor, id : String) : Array<String> {
    var now = haxe.Timer.stamp();
    if (editor.commands.revision != cacheRevision || now - cacheTime > CACHE_SECONDS) {
      cacheRevision = editor.commands.revision;
      cacheTime = now;
      startersCache = [];
      var fields = dialogFields(editor);
      for (key in editor.dialogs.ids()) startersCache.set(key, scan(editor, fields, key));
    }
    var found = startersCache.get(id);
    return found == null ? [] : found;
  }

  public static function describe(found : Array<String>) {
    var shown = found.slice(0, LIMIT).join(", ");
    return found.length > LIMIT ? '$shown ve ${found.length - LIMIT} yer daha' : shown;
  }

  static function scan(editor : Editor, fields : Map<String, Array<String>>, id : String) : Array<String> {
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
    return found;
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

  static function dialogFields(editor : Editor) {
    return fieldsOf(editor.scene.registry, hint -> switch (hint) {
      case HDialog: true;
      default: false;
    });
  }

  // Aranan bağlantıyı taşıyan alanlar, bileşen kimliğine göre.
  static function fieldsOf(registry : scene.ComponentRegistry, matches : FieldHint->Bool) {
    var fields = new Map<String, Array<String>>();
    for (type in registry.currentTypes()) {
      var sample = registry.create(type);
      for (field in sample.describeFields()) {
        if (!matches(field.hint)) continue;
        if (!fields.exists(type)) fields.set(type, []);
        fields.get(type).push(field.name);
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
