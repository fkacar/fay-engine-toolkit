package scene.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import scene.data.SceneSchema;
import sys.FileSystem;
import sys.io.File;

// Derleme sırasında sahne dosyalarını kodla karşılaştırır. Bileşen veya alan adı değişip
// sahne güncellenmediyse derleme durur; böylece sorun değişikliği yapan geliştiriciye çıkar.
//
//   --macro scene.macro.SceneCheck.run("res/scenes")
class SceneCheck {
  static inline var SCENE_EXTENSION = ".scene.json";

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
        for (problem in schema.check(File.getContent(path))) {
          Context.reportError(problem, pos);
          failed = true;
        }
      }
      if (failed) Context.fatalError("Sahne dosyaları kodla uyuşmuyor", Context.currentPos());
    });
  }

  static function sceneFiles(directory : String) {
    if (!FileSystem.exists(directory)) return [];
    return FileSystem.readDirectory(directory).filter(name -> StringTools.endsWith(name, SCENE_EXTENSION));
  }

  static function addComponent(schema : SceneSchema, cls : ClassType) {
    if (!cls.meta.has(":component")) return;
    var ids = strings(cls.meta.extract(":component")).concat(strings(cls.meta.extract(":formerly")));
    var fields = new Map<String, String>();
    var current = cls;
    while (current != null) {
      for (field in current.fields.get()) {
        if (!field.meta.has(":editable")) continue;
        var kind = TypeTools.toString(field.type);
        fields.set(field.name, kind);
        for (former in strings(field.meta.extract(":formerly"))) fields.set(former, kind);
      }
      current = current.superClass == null ? null : current.superClass.t.get();
    }
    schema.add(ids, fields);
  }

  static function strings(entries : Array<haxe.macro.Expr.MetadataEntry>) : Array<String> {
    var values = [];
    for (entry in entries) for (param in entry.params) values.push(haxe.macro.ExprTools.getValue(param));
    return values;
  }
}
#end
