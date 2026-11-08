package scene.editor;

import scene.data.ThreeWay;
import scene.editor.commands.SetDialogCommand;
import scene.story.Dialog;
import sys.FileSystem;
import sys.io.File;

// Editörde açık diyaloglar. Her diyalog ayrı dosyadır, sahneyle birlikte kaydedilir.
class DialogStore {
  public static inline var DIRECTORY = "res/" + Dialog.DIRECTORY;

  public var dialogs(default, null) = new Map<String, Dialog>();
  // Koşul düğümündeki eşya bu tablodan seçilir; satır silinirken diyaloglar da taranır. Oyun belirler.
  public var itemTable : Null<String>;
  // İlişki koşulunun fraksiyon tablosu (oyun bağlar).
  public var factionTable : Null<String>;
  // Konuşanların tablosu (oyun bildirir): satırın konuşanı bu tablonun kimliğidir, adı orada yazılır ve çevrilir.
  public var speakerTable : Null<String>;

  var disk = new Map<String, String>();
  var editor : Null<Editor>;

  public function new() {
    reload();
  }

  public function attach(editor : Editor) {
    this.editor = editor;
    for (id => text in disk) editor.diskGuard.observe(pathOf(id), text);
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
      if (editor != null) editor.diskGuard.observe(pathOf(id), text);
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

  // Dışarıda değişen diyalog kör yazılmaz: düğüm düğüm birleşir, çakışırsa kaydedilmez.
  public function save() {
    var files = new Map<String, Null<String>>();
    for (id => dialog in dialogs) {
      var text = dialog.write();
      if (disk.get(id) != text) files.set(id, text);
    }
    for (id in disk.keys()) if (!dialogs.exists(id)) files.set(id, null);
    if (Lambda.count(files) > 0 && !FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
    return StoreGuard.save(editor, access(), files);
  }

  public function unsavedFiles() : Array<String> {
    var access = access();
    return [for (name in access.names()) if (access.mine(name) != access.base(name)) access.path(name)];
  }

  public function editorText(path : String) : Null<String> {
    var access = access();
    for (name in access.names()) if (access.path(name) == path) return access.mine(name);
    return null;
  }

  public function checkDisk() : Array<String> {
    return StoreGuard.check(editor, access());
  }

  function pathOf(id : String) {
    return '$DIRECTORY/$id${Dialog.SUFFIX}';
  }

  function access() : StoreGuard.StoreAccess {
    return {
      path: pathOf,
      names: () -> {
        var found = [for (id in disk.keys()) id];
        for (id in dialogs.keys()) if (found.indexOf(id) < 0) found.push(id);
        if (FileSystem.exists(DIRECTORY))
          for (file in FileSystem.readDirectory(DIRECTORY)) {
            if (!StringTools.endsWith(file, Dialog.SUFFIX)) continue;
            var id = file.substr(0, file.length - Dialog.SUFFIX.length);
            if (found.indexOf(id) < 0) found.push(id);
          }
        found;
      },
      base: id -> disk.get(id),
      setBase: (id, text) -> {
        if (text == null) disk.remove(id);
        else disk.set(id, text);
      },
      mine: text,
      apply: apply,
      forget: id -> editor.commands.forget(command -> Std.isOfType(command, SetDialogCommand) && cast(command, SetDialogCommand).id == id),
      merge: (id, base, mine, theirs, prefer) -> ThreeWay.dialog(id, base, mine, theirs, prefer),
      canonical: (id, text) -> try Dialog.read(id, text).write() catch (e : Dynamic) text,
    };
  }
}
