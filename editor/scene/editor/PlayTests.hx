package scene.editor;

import scene.PlayFiles;
import sys.FileSystem;
import sys.io.File;

// Görev testi dosyaları ve editörle oyun arasındaki sonuç dosyası.
class PlayTests {
  // Son çalıştırılan kayıtlı testin adı; tarifle (playtest) çalışınca boş.
  public static var lastName : Null<String>;

  public static function list() : Array<String> {
    if (!FileSystem.exists(PlayFiles.TESTS)) return [];
    var names = [for (file in FileSystem.readDirectory(PlayFiles.TESTS)) if (StringTools.endsWith(file, PlayFiles.TEST_SUFFIX)) file.substr(0, file.length - PlayFiles.TEST_SUFFIX.length)];
    names.sort(Reflect.compare);
    return names;
  }

  public static function load(name : String) : Null<Dynamic> {
    var path = '${PlayFiles.TESTS}/$name${PlayFiles.TEST_SUFFIX}';
    return FileSystem.exists(path) ? try haxe.Json.parse(File.getContent(path)) catch (e : Dynamic) null : null;
  }

  // Eski sonuç silinir, oyun açılınca senaryoyu okur.
  public static function prepare(test : Dynamic) {
    if (!FileSystem.exists("bin")) FileSystem.createDirectory("bin");
    if (!FileSystem.exists(PlayFiles.DIRECTORY)) FileSystem.createDirectory(PlayFiles.DIRECTORY);
    if (FileSystem.exists(PlayFiles.RESULT)) FileSystem.deleteFile(PlayFiles.RESULT);
    File.saveContent(PlayFiles.SCRIPT, haxe.Json.stringify(test, null, " "));
  }

  public static function result() : Null<Dynamic> {
    if (!FileSystem.exists(PlayFiles.RESULT)) return null;
    return try haxe.Json.parse(File.getContent(PlayFiles.RESULT)) catch (e : Dynamic) null;
  }
}
