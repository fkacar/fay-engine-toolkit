package scene.editor;

import scene.data.DataTable;
import sys.FileSystem;
import sys.io.File;

// Editörde açık tablolar. Değişiklikler komutla yapılır, sahneyle birlikte kaydedilir.
class DataStore {
  public static inline var DIRECTORY = "res/data";

  public var tables(default, null) = new Map<String, DataTable>();

  var disk = new Map<String, String>();

  public function new() {
    reload();
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
  public function apply(name : String, text : Null<String>) {
    if (text == null) tables.remove(name);
    else tables.set(name, DataTable.read(name, text));
  }

  public function isDirty() {
    return Lambda.count(changed()) > 0;
  }

  public function save() {
    var files = changed();
    if (Lambda.count(files) > 0 && !FileSystem.exists(DIRECTORY)) FileSystem.createDirectory(DIRECTORY);
    for (name => text in files) {
      var path = '$DIRECTORY/$name${DataTable.SUFFIX}';
      if (text == null) {
        if (FileSystem.exists(path)) FileSystem.deleteFile(path);
        disk.remove(name);
      } else {
        File.saveContent(path, text);
        disk.set(name, text);
      }
    }
    return Lambda.count(files);
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
