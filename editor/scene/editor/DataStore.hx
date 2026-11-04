package scene.editor;

import scene.data.DataTable;
import scene.data.ThreeWay;
import scene.editor.commands.SetTableCommand;
import sys.FileSystem;
import sys.io.File;

// Editörde açık tablolar. Değişiklikler komutla yapılır, sahneyle birlikte kaydedilir.
class DataStore {
  public static inline var DIRECTORY = "res/data";

  public var tables(default, null) = new Map<String, DataTable>();

  var disk = new Map<String, String>();
  var editor : Null<Editor>;

  public function new() {
    reload();
  }

  public function attach(editor : Editor) {
    this.editor = editor;
    for (name => text in disk) editor.diskGuard.observe(pathOf(name), text);
  }

  // Kaydedilmeden bırakılan değişiklikler atılır.
  public function reload() {
    tables = new Map();
    disk = new Map();
    if (!FileSystem.exists(DIRECTORY)) return;
    for (file in FileSystem.readDirectory(DIRECTORY)) {
      if (!StringTools.endsWith(file, DataTable.SUFFIX)) continue;
      var name = file.substr(0, file.length - DataTable.SUFFIX.length);
      var text = File.getContent('$DIRECTORY/$file');
      disk.set(name, text);
      if (editor != null) editor.diskGuard.observe(pathOf(name), text);
      try tables.set(name, DataTable.read(name, text)) catch (e : Dynamic) {}
    }
  }

  public function names() : Array<String> {
    var names = [for (name in tables.keys()) name];
    names.sort(Reflect.compare);
    return names;
  }

  public function exists(table : String, id : String) {
    var data = tables.get(table);
    return data != null && data.find(id) != null;
  }

  public function text(name : String) : Null<String> {
    var table = tables.get(name);
    return table == null ? null : table.write();
  }

  // Komutlar tablonun tamamını metin olarak değiştirir; null tabloyu kaldırır.
  // Tablo uygulanınca (düzenleme, geri alma, ajan) hemen çağrılır: oyun kendi önbelleğini boşaltır, aynı karedeki
  // sonraki okuma yeni tabloyu görür.
  public var onApplied : Null<String -> Void>;

  public function apply(name : String, text : Null<String>) {
    if (text == null) tables.remove(name);
    else tables.set(name, DataTable.read(name, text));
    if (onApplied != null) onApplied(name);
  }

  public function isDirty() {
    return Lambda.count(changed()) > 0;
  }

  // Dışarıda değişen tablo kör yazılmaz: satır satır birleşir, çakışırsa kaydedilmez.
  public function save() {
    if (Lambda.count(changed()) > 0 && !FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
    return StoreGuard.save(editor, access(), changed());
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

  function pathOf(name : String) {
    return '$DIRECTORY/$name${DataTable.SUFFIX}';
  }

  function access() : StoreGuard.StoreAccess {
    return {
      path: pathOf,
      names: () -> {
        var found = [for (name in disk.keys()) name];
        for (name in tables.keys()) if (found.indexOf(name) < 0) found.push(name);
        if (FileSystem.exists(DIRECTORY))
          for (file in FileSystem.readDirectory(DIRECTORY)) {
            if (!StringTools.endsWith(file, DataTable.SUFFIX)) continue;
            var name = file.substr(0, file.length - DataTable.SUFFIX.length);
            if (found.indexOf(name) < 0) found.push(name);
          }
        found;
      },
      base: name -> disk.get(name),
      setBase: (name, text) -> {
        if (text == null) disk.remove(name);
        else disk.set(name, text);
      },
      mine: text,
      apply: apply,
      forget: name -> editor.commands.forget(command -> Std.isOfType(command, SetTableCommand) && cast(command, SetTableCommand).name == name),
      merge: (name, base, mine, theirs, prefer) -> ThreeWay.table(name, base, mine, theirs, prefer),
      canonical: (name, text) -> try DataTable.read(name, text).write() catch (e : Dynamic) text,
    };
  }

  function changed() : Map<String, Null<String>> {
    var files = new Map<String, Null<String>>();
    for (name => table in tables) {
      var text = table.write();
      if (disk.get(name) != text) files.set(name, text);
    }
    for (name in disk.keys()) if (!tables.exists(name)) files.set(name, null);
    return files;
  }
}
