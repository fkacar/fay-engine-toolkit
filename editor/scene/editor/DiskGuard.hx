package scene.editor;

import sys.FileSystem;
import sys.io.File;

typedef FileConflict = {
  var path : String;
  var units : Array<String>;
  var resolve : String->Void;  // ThreeWay.MINE veya ThreeWay.THEIRS
}

// Editör dosyayı hiçbir zaman kör yazmaz. Açık dosyalar dışarıda (git pull, metin editörü, LLM ajanı)
// değişirse: kaydedilmemiş değişiklik yoksa editör yeniden yükler, varsa kaydederken birim birim
// birleştirir. Aynı birim iki tarafta da değiştiyse dosya kaydedilmez, iki hal yedeklenir ve
// tasarımcı Uyarılar panelinden seçer. Hiçbir durumda iş sessizce kaybolmaz.
class DiskGuard {
  public static inline var BACKUP_DIRECTORY = ".editor/catismalar";
  static inline var CHECK_SECONDS = 1.;
  static inline var RECENT_SECONDS = 2.;

  public var conflicts(default, null) : Array<FileConflict> = [];
  // Dışarıda değişti ama editörde kaydedilmemiş değişiklik var: kaydederken birleşecek.
  public var pending(default, null) = new Map<String, Bool>();

  var seen = new Map<String, Null<String>>();
  var stamps = new Map<String, String>();
  var timer = 0.;

  public function new() {}

  public function due(dt : Float) {
    timer += dt;
    if (timer < CHECK_SECONDS) return false;
    timer = 0;
    return true;
  }

  public static function read(path : String) : Null<String> {
    return FileSystem.exists(path) ? File.getContent(path) : null;
  }

  // Editörün bildiği disk hali: okuduğu veya yazdığı.
  public function observe(path : String, text : Null<String>) {
    seen.set(path, text);
    stamps.set(path, stampOf(path));
    pending.remove(path);
  }

  public function write(path : String, text : String) {
    var directory = haxe.io.Path.directory(path);
    if (directory != "" && !FileSystem.exists(directory)) FileSystem.createDirectory(directory);
    File.saveContent(path, text);
    observe(path, text);
  }

  public function delete(path : String) {
    if (FileSystem.exists(path)) FileSystem.deleteFile(path);
    observe(path, null);
  }

  // Bilinen halden farklıysa yeni içeriği verir. Değişme zamanı saniye çözünürlüklü olduğundan
  // yeni değişmiş dosya içerikten de karşılaştırılır: aynı saniyedeki iki yazma kaçmaz.
  public function changed(path : String) : Null<{text : Null<String>}> {
    var stamp = stampOf(path);
    if (seen.exists(path) && stamp == stamps.get(path) && !isRecent(path)) return null;
    stamps.set(path, stamp);
    var text = read(path);
    if (seen.exists(path) && seen.get(path) == text) return null;
    seen.set(path, text);
    return {text: text};
  }

  public function backup(path : String, mine : Null<String>, theirs : Null<String>) {
    if (!FileSystem.exists(BACKUP_DIRECTORY)) FileSystem.createDirectory(BACKUP_DIRECTORY);
    var name = DateTools.format(Date.now(), "%Y%m%d-%H%M%S") + "-" + StringTools.replace(StringTools.replace(path, "/", "_"), "\\", "_");
    if (mine != null) File.saveContent('$BACKUP_DIRECTORY/$name.benim', mine);
    if (theirs != null) File.saveContent('$BACKUP_DIRECTORY/$name.disk', theirs);
  }

  public function addConflict(path : String, units : Array<String>, resolve : String->Void) {
    removeConflict(path);
    conflicts.push({path: path, units: units, resolve: resolve});
    pending.remove(path);
  }

  public function removeConflict(path : String) {
    conflicts = conflicts.filter(conflict -> conflict.path != path);
  }

  public function hasConflict(path : String) {
    return Lambda.exists(conflicts, conflict -> conflict.path == path);
  }

  public function forgetAll() {
    conflicts = [];
    pending = new Map();
    seen = new Map();
    stamps = new Map();
  }

  function isRecent(path : String) {
    if (!FileSystem.exists(path)) return false;
    return Date.now().getTime() - FileSystem.stat(path).mtime.getTime() < RECENT_SECONDS * 1000;
  }

  static function stampOf(path : String) {
    if (!FileSystem.exists(path)) return "yok";
    var stat = FileSystem.stat(path);
    return '${stat.mtime.getTime()}:${stat.size}';
  }
}
