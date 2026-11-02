package scene.editor;

import scene.story.Dialog;
import sys.FileSystem;
import sys.io.File;

// Editörde açık diyaloglar. Her diyalog ayrı dosyadır, sahneyle birlikte kaydedilir.
class DialogStore {
  public static inline var DIRECTORY = "res/" + Dialog.DIRECTORY;

  public var dialogs(default, null) = new Map<String, Dialog>();
  // Koşul düğümündeki eşya bu tablodan seçilir; satır silinirken diyaloglar da taranır. Oyun belirler.
  public var itemTable : Null<String>;

  var disk = new Map<String, String>();

  public function new() {
    reload();
  }

  public function reload() {
    dialogs = new Map();
    disk = new Map();
    if (!FileSystem.exists(DIRECTORY)) return;
    for (file in FileSystem.readDirectory(DIRECTORY)) {
      if (!StringTools.endsWith(file, Dialog.SUFFIX)) continue;
      var id = file.substr(0, file.length - Dialog.SUFFIX.length);
      var text = File.getContent('$DIRECTORY/$file');
      disk.set(id, text);
      try dialogs.set(id, Dialog.read(id, text)) catch (e : Dynamic) {}
    }
  }

  public function ids() : Array<String> {
    var ids = [for (id in dialogs.keys()) id];
    ids.sort(Reflect.compare);
    return ids;
  }

  public function exists(id : String) {
    return dialogs.exists(id);
  }

  public function text(id : String) : Null<String> {
    var dialog = dialogs.get(id);
    return dialog == null ? null : dialog.write();
  }

  public function apply(id : String, text : Null<String>) {
    if (text == null) dialogs.remove(id);
    else dialogs.set(id, Dialog.read(id, text));
  }

  public function save() {
    var count = 0;
    for (id => dialog in dialogs) {
      var text = dialog.write();
      if (disk.get(id) == text) continue;
      if (!FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
      File.saveContent('$DIRECTORY/$id${Dialog.SUFFIX}', text);
      disk.set(id, text);
      count++;
    }
    for (id in [for (key in disk.keys()) key]) if (!dialogs.exists(id)) {
      var path = '$DIRECTORY/$id${Dialog.SUFFIX}';
      if (FileSystem.exists(path)) FileSystem.deleteFile(path);
      disk.remove(id);
      count++;
    }
    return count;
  }
}
