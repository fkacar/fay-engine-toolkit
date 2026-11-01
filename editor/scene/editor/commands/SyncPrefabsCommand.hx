package scene.editor.commands;

import scene.Entity;
import scene.SceneInstance;
import scene.data.SceneData.EntityData;

typedef PrefabFile = {
  var path : String;
  var before : String;
  var after : String;
  var write : String->Void;
}

// Bir instance'ın farklarını siler, istenirse prefab dosyasını da değiştirir. Aynı dosyayı
// kullanan bütün kopyalar yerinde güncellenir, geri alınınca dosya da eski haline döner.
class SyncPrefabsCommand implements Command {
  public var label(default, null) : String;

  var scene : SceneInstance;
  var before : Array<EntityData>;
  var after : Array<EntityData>;
  var file : Null<PrefabFile>;

  public function new(label : String, scene : SceneInstance, root : Entity, ?file : PrefabFile) {
    this.label = label;
    this.scene = scene;
    this.file = file;
    before = scene.instances();
    after = [for (item in before) item.id == root.id ? withoutOverrides(item) : item];
  }

  public function execute() {
    apply(after, file == null ? null : file.after);
  }

  public function undo() {
    apply(before, file == null ? null : file.before);
  }

  function apply(instances : Array<EntityData>, text : Null<String>) {
    if (text != null) {
      file.write(text);
      scene.forgetPrefab(file.path);
    }
    for (instance in instances) scene.syncInstance(instance);
  }

  static function withoutOverrides(item : EntityData) {
    var copy = item.clone();
    copy.overrides = [];
    return copy;
  }
}
