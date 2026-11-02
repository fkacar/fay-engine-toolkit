package scene.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import scene.data.SceneFormat;
import scene.data.SceneSchema;
import sys.FileSystem;
import sys.io.File;

// Derleme sırasında sahne dosyalarını kodla karşılaştırır. Bileşen veya alan adı değişip
// sahne güncellenmediyse derleme durur; böylece sorun değişikliği yapan geliştiriciye çıkar.
//
//   --macro scene.macro.SceneCheck.run("res/scenes")
//   --macro scene.macro.SceneCheck.run("res/prefabs")
class SceneCheck {
  static inline var SCENE_EXTENSION = ".scene.json";
  static inline var PREFAB_EXTENSION = ".prefab.json";

  public static function run(directory : String) {
    Context.onAfterTyping(types -> {
      var schema = new SceneSchema();
      for (type in types)
        switch (type) {
          case TClassDecl(cls): addComponent(schema, cls.get());
          default:
        }
      var failed = false;
      for (name in sceneFiles(directory)) {
        var path = directory + "/" + name;
        var pos = Context.makePosition({file: path, min: 0, max: 0});
        var resources = haxe.io.Path.directory(directory);
        for (problem in schema.check(File.getContent(path), prefab -> FileSystem.exists('$resources/$prefab'), (table, id) -> rowExists('$resources/${scene.data.GameData.DIRECTORY}', table, id))) {
          Context.reportError(problem, pos);
          failed = true;
        }
        for (warning in schema.warnings) Context.warning(warning, pos);
        // Okunamayan dosya yukarıda hata olarak raporlandı.
        var prefab = StringTools.endsWith(name, PREFAB_EXTENSION) ? try SceneFormat.read(File.getContent(path)) catch (e : Dynamic) null : null;
        if (prefab != null && scene.data.Prefabs.rootOf(prefab) == null)
          Context.warning('$name: prefab tek köklü olmalı. Oyunda bu prefab\'ın kopyaları boş kalır, editörde nesneleri tek kökün altına al.', pos);
      }
      if (failed) Context.fatalError("Sahne dosyaları kodla uyuşmuyor", Context.currentPos());
    });
  }

  static var tables = new Map<String, Null<scene.data.DataTable>>();

  static inline var DIALOG_REFERENCE = "@diyalog";

  static function rowExists(directory : String, table : String, id : String) {
    if (table == DIALOG_REFERENCE)
      return FileSystem.exists(haxe.io.Path.directory(directory) + '/${scene.story.Dialog.DIRECTORY}/$id${scene.story.Dialog.SUFFIX}');
    var path = '$directory/$table${scene.data.DataTable.SUFFIX}';
    if (!tables.exists(path)) tables.set(path, FileSystem.exists(path) ? scene.data.DataTable.read(table, File.getContent(path)) : null);
    var data = tables.get(path);
    return data != null && data.find(id) != null;
  }

  static function sceneFiles(directory : String) {
    if (!FileSystem.exists(directory)) return [];
    return FileSystem.readDirectory(directory).filter(name -> StringTools.endsWith(name, SCENE_EXTENSION) || StringTools.endsWith(name, PREFAB_EXTENSION));
  }

  static function addComponent(schema : SceneSchema, cls : ClassType) {
    if (!cls.meta.has(":component")) return;
    var ids = strings(cls.meta.extract(":component")).concat(strings(cls.meta.extract(":formerly")));
    var fields = new Map<String, String>();
    var options = new Map<String, Array<String>>();
    var refs = new Map<String, String>();
    var current = cls;
    while (current != null) {
      for (field in current.fields.get()) {
        if (!field.meta.has(":editable")) continue;
        var kind = TypeTools.toString(field.type);
        var names = [field.name].concat(strings(field.meta.extract(":formerly")));
        for (name in names) {
          fields.set(name, kind);
          if (field.meta.has(":choice")) options.set(name, strings(field.meta.extract(":choice")));
          if (field.meta.has(":ref")) refs.set(name, strings(field.meta.extract(":ref"))[0]);
          if (field.meta.has(":dialog")) refs.set(name, DIALOG_REFERENCE);
        }
      }
      current = current.superClass == null ? null : current.superClass.t.get();
    }
    schema.add(ids, fields, options, refs);
  }

  static function strings(entries : Array<haxe.macro.Expr.MetadataEntry>) : Array<String> {
    var values = [];
    for (entry in entries) for (param in entry.params) values.push(haxe.macro.ExprTools.getValue(param));
    return values;
  }
}
#end
