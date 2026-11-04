package scene.editor;

import haxe.io.Path;
import sys.FileSystem;

// Modeli başsız Blender'dan geçirip FBX yazar (tools/blender_fbx.py). Heaps 2.1 yalnızca FBX okur: GLB, glTF ve
// OBJ hep geçer; FBX ayarda "blender": true ise geçer (başka aracın ölçeğiyle yazılmış, kemikleri 100 kat büyük ya
// da klipleri sabit kare hızında olmayan dosya). Çıktı türetilmiş dosyadır, .editor/donusum altında durur ve depoya
// girmez. Kaynak ya da betik değişmedikçe yeniden çevrilmez. Blender: BLENDER ortam değişkeni, yoksa Mac ve Windows'un bilinen
// kurulum yerleri.
class BlenderConverter {
  public static inline var CACHE = ".editor/donusum";
  public static var SCRIPT = "libs/scene-toolkit/tools/blender_fbx.py";
  static var TYPES = ["glb", "gltf", "obj"];

  public static function handles(source : String) : Bool {
    return TYPES.indexOf(Path.extension(source).toLowerCase()) >= 0;
  }

  // Kaynağın çevrilmiş FBX'inin yeri (assets'e göre aynı düzen).
  public static function cachePath(source : String) : String {
    var relative = StringTools.replace(source, "\\", "/");
    if (StringTools.startsWith(relative, "assets/")) relative = relative.substr("assets/".length);
    return '$CACHE/${Path.withoutExtension(relative)}.fbx';
  }

  // Çevrilmiş FBX'in yolu; gerekirse çevirir. Blender yoksa ya da çeviri başarısızsa hata.
  public static function convert(source : String) : String {
    var target = cachePath(source);
    // FBX kaynağın kendi adıyla karışmasın.
    if (Path.extension(source).toLowerCase() == "fbx") target = Path.withoutExtension(target) + ".blender.fbx";
    // Kaynak ya da çeviri betiği değişmediyse önceki çıktı geçerli.
    var built = FileSystem.exists(target) ? FileSystem.stat(target).mtime.getTime() : -1.;
    var script = FileSystem.exists(SCRIPT) ? FileSystem.stat(SCRIPT).mtime.getTime() : 0.;
    if (built >= FileSystem.stat(source).mtime.getTime() && built >= script) return target;
    var blender = find();
    if (blender == null) throw "Bu model için Blender gerekli: Blender'ı kurun ya da BLENDER ortam değişkenine yolunu yazın";
    if (!FileSystem.exists(SCRIPT)) throw 'çeviri betiği yok: $SCRIPT';
    makeDirectory(Path.directory(target));
    if (FileSystem.exists(target)) FileSystem.deleteFile(target);
    var process = new sys.io.Process(blender, ["-b", "--factory-startup", "--python", SCRIPT, "--", FileSystem.fullPath(source), FileSystem.fullPath(".") + "/" + target]);
    var output = process.stdout.readAll().toString();
    var errors = process.stderr.readAll().toString();
    var code = process.exitCode();
    process.close();
    if (code != 0 || !FileSystem.exists(target) || output.indexOf("BLENDER_FBX_TAMAM") < 0) {
      var lines = (errors + "\n" + output).split("\n").filter(line -> line.indexOf("Error") >= 0 || line.indexOf("rror:") >= 0);
      throw 'Blender modeli çeviremedi (çıkış $code): ${lines.slice(0, 3).join(" / ")}';
    }
    return target;
  }

  public static function find() : Null<String> {
    var env = Sys.getEnv("BLENDER");
    if (env != null && env != "" && FileSystem.exists(env)) return env;
    var mac = "/Applications/Blender.app/Contents/MacOS/Blender";
    if (FileSystem.exists(mac)) return mac;
    // Windows: Program Files altındaki en yeni sürüm.
    var root = "C:/Program Files/Blender Foundation";
    if (FileSystem.exists(root) && FileSystem.isDirectory(root)) {
      var versions = FileSystem.readDirectory(root).filter(name -> FileSystem.exists('$root/$name/blender.exe'));
      versions.sort(Reflect.compare);
      if (versions.length > 0) return '$root/${versions[versions.length - 1]}/blender.exe';
    }
    return null;
  }

  static function makeDirectory(directory : String) {
    if (directory == "" || FileSystem.exists(directory)) return;
    makeDirectory(Path.directory(directory));
    FileSystem.createDirectory(directory);
  }
}
