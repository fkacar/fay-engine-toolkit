package scene.editor;

import scene.data.DataTable;
import scene.data.ThreeWay;
import scene.editor.commands.SetTableCommand;
import sys.FileSystem;
import sys.io.File;

// Editörde açık tablolar. Değişiklikler komutla yapılır, sahneyle birlikte kaydedilir.
// İkinci bir örnek çevirileri tutar (Editor.translations): klasör res/ceviri, alt klasörler dil, ad "<dil>/<tablo>"
// (scene.data.Translations). Geri alma, kaydetme, dışarıda değişen dosyayla birleştirme ikisinde de aynıdır.
class DataStore {
  public static inline var DIRECTORY = "res/data";
  // res/ + scene.data.Translations.DIRECTORY
  public static inline var TRANSLATION_DIRECTORY = "res/ceviri";

  public var tables(default, null) = new Map<String, DataTable>();
  public var directory(default, null) : String;
  // Alt klasörlü depo (çeviriler): tablolar <klasör>/<alt klasör>/<ad>.table.json, adı "<alt klasör>/<ad>".
  public var nested(default, null) : Bool;

  var disk = new Map<String, String>();
  var editor : Null<Editor>;

  public function new(?directory : String, nested = false) {
    this.directory = directory == null ? DIRECTORY : directory;
    this.nested = nested;
    reload();
  }

  // Klasördeki tablo adları. Alt klasörlüyse her derinlikte "<alt klasör>/.../<ad>" (çeviri: "tr/esyalar",
  // "tr/diyaloglar/berber").
  function filesOnDisk() : Array<String> {
    var found = [];
    if (!FileSystem.exists(directory)) return found;
    function scan(folder : String) {
      var path = folder == "" ? directory : '$directory/$folder';
      for (file in FileSystem.readDirectory(path)) {
        var child = folder == "" ? file : '$folder/$file';
        if (FileSystem.isDirectory('$path/$file')) {
          if (nested) scan(child);
        } else if (StringTools.endsWith(file, DataTable.SUFFIX) && (!nested || folder != ""))
          found.push(child.substr(0, child.length - DataTable.SUFFIX.length));
      }
    }
    scan("");
    return found;
  }

  static function baseName(name : String) : String {
    var slash = name.lastIndexOf("/");
    return slash < 0 ? name : name.substr(slash + 1);
  }

  public function attach(editor : Editor) {
    this.editor = editor;
    for (name => text in disk) editor.diskGuard.observe(pathOf(name), text);
  }

  // Kaydedilmeden bırakılan değişiklikler atılır.
  public function reload() {
    tables = new Map();
    disk = new Map();
    for (name in filesOnDisk()) {
      var text = File.getContent(pathOf(name));
      disk.set(name, text);
      if (editor != null) editor.diskGuard.observe(pathOf(name), text);
      try tables.set(name, DataTable.read(baseName(name), text)) catch (e : Dynamic) {}
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
    else tables.set(name, DataTable.read(baseName(name), text));
    if (onApplied != null) onApplied(name);
  }

  public function isDirty() {
    return Lambda.count(changed()) > 0;
  }

  // Dışarıda değişen tablo kör yazılmaz: satır satır birleşir, çakışırsa kaydedilmez.
  public function save() {
    for (name => text in changed()) if (text != null) {
      var folder = haxe.io.Path.directory(pathOf(name));
      if (!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
    }
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

  public function pathOf(name : String) {
    return '$directory/$name${DataTable.SUFFIX}';
  }

  function access() : StoreGuard.StoreAccess {
    return {
      path: pathOf,
      names: () -> {
        var found = [for (name in disk.keys()) name];
        for (name in tables.keys()) if (found.indexOf(name) < 0) found.push(name);
        for (name in filesOnDisk()) if (found.indexOf(name) < 0) found.push(name);
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
      merge: (name, base, mine, theirs, prefer) -> ThreeWay.table(baseName(name), base, mine, theirs, prefer),
      canonical: (name, text) -> try DataTable.read(baseName(name), text).write() catch (e : Dynamic) text,
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
