package scene.editor;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

typedef ImportResult = {
  var target : Null<String>;
  var problems : Array<String>;
  var ?triangles : Int;
  var ?parts : Int;
}

// `assets` ham kaynakları, `res` oyunun kullandıklarını tutar. FBX burada dönüştürülür ve
// `res` altına HMD olarak yazılır: oyun derlemesi FBX'i makro içinde dönüştürür, normal
// map'li modelde `meshTools` ister ve durur. HMD'de derleme zamanı dönüşümü yoktur.
private typedef FbxTools = hxd.fmt.fbx.Data.FbxTools;

class AssetImporter {
  static inline var SOURCE_DIRECTORY = "assets";
  static inline var TARGET_DIRECTORY = "res/models";
  static inline var WHITE_TEXTURE = "white.png";

  static var TEXTURE_TYPES = ["png", "jpg", "jpeg", "tga", "dds", "hdr"];

  public function new() {}

  public function pending() : Array<String> {
    var found = [];
    collect(SOURCE_DIRECTORY, found);
    found.sort(Reflect.compare);
    return found.filter(needsImport);
  }

  public function targetOf(source : String) {
    var name = SceneDocument.cleanName(Path.withoutDirectory(Path.withoutExtension(source)));
    return '$TARGET_DIRECTORY/$name/$name.hmd';
  }

  // target verilmezse model `res/models` altına yazılır.
  public function run(source : String, ?target : String) : ImportResult {
    var hmd = try convert(source) catch (e : Dynamic) return {target: null, problems: ['$source dönüştürülemedi: $e']};

    if (target == null) target = targetOf(source);
    createDirectory(Path.directory(target));
    var problems = [];
    for (material in hmd.materials) {
      material.diffuseTexture = bringTexture(material.diffuseTexture, source, target, problems);
      material.specularTexture = bringTexture(material.specularTexture, source, target, problems);
      material.normalMap = bringTexture(material.normalMap, source, target, problems);
      // Bu haritaların gölgelendiricisi UV'yi temel renk dokusundan alır, o yoksa çizim hata verir.
      // Yalnızca normal map'i olan malzemeler yaygındır: beyaz doku rengi değiştirmez, detay korunur.
      if (material.diffuseTexture == null && (material.normalMap != null || material.specularTexture != null))
        material.diffuseTexture = whiteTexture(target);
    }

    var out = new haxe.io.BytesOutput();
    new hxd.fmt.hmd.Writer(out).write(hmd);
    File.saveBytes(target, out.getBytes());
    forgetMissingFiles();
    var triangles = 0;
    for (geometry in hmd.geometries) triangles += Std.int(geometry.indexCount / 3);
    return {target: target, problems: problems, triangles: triangles, parts: hmd.geometries.length};
  }

  // Heaps tek bir dokuyu bulamazsa modelin tamamını yüklemez. Bu yüzden eksik veya
  // desteklenmeyen doku modelden çıkarılır: tasarımcı modeli görür, eksik uyarı olarak kalır.
  function bringTexture(texture : Null<String>, source : String, target : String, problems : Array<String>) : Null<String> {
    if (texture == null) return null;
    var name = Path.withoutDirectory(StringTools.replace(texture, "\\", "/"));
    if (TEXTURE_TYPES.indexOf(Path.extension(name).toLowerCase()) < 0) {
      problems.push('$source: desteklenmeyen doku modelden çıkarıldı: $name');
      return null;
    }
    var found = findFile(Path.directory(source), name);
    if (found == null) {
      problems.push('$source: bulunamayan doku modelden çıkarıldı: $name');
      return null;
    }
    File.copy(found, Path.directory(target) + "/" + name);
    return name;
  }

  function whiteTexture(target : String) {
    var pixels = hxd.Pixels.alloc(1, 1, RGBA);
    pixels.setPixel(0, 0, 0xFFFFFFFF);
    File.saveBytes(Path.directory(target) + "/" + WHITE_TEXTURE, pixels.toPNG());
    return WHITE_TEXTURE;
  }

  // Kaynak güncellenince model yeniden alınabilir olur, sahnelerdeki yol değişmez.
  function needsImport(source : String) {
    var target = targetOf(source);
    return !FileSystem.exists(target) || FileSystem.stat(source).mtime.getTime() > FileSystem.stat(target).mtime.getTime();
  }

  function convert(source : String) {
    var root = hxd.fmt.fbx.Parser.parse(File.getBytes(source));
    unpackTextures(root, source);
    var out = new hxd.fmt.fbx.HMDOut(source);
    out.load(root);
    return out.toHMD(null, true);
  }

  // "Dokuları göm" ile dışa aktarılan dosyada dokular FBX'in içindedir. Yanına çıkarılır,
  // böylece dokusu ayrı gelen dosyayla aynı yoldan alınır.
  function unpackTextures(root : hxd.fmt.fbx.Data.FbxNode, source : String) {
    for (video in FbxTools.getAll(root, "Objects.Video")) {
      var content = FbxTools.getAll(video, "Content");
      var names = FbxTools.getAll(video, "RelativeFilename").concat(FbxTools.getAll(video, "FileName"));
      if (content.length == 0 || names.length == 0) continue;
      var bytes = switch (content[0].props[0]) {
        case hxd.fmt.fbx.Data.FbxProp.PBinary(data): data;
        default: null;
      };
      if (bytes == null || bytes.length == 0) continue;
      var name = Path.withoutDirectory(StringTools.replace(FbxTools.toString(names[0].props[0]), "\\", "/"));
      var target = Path.directory(source) + "/" + name;
      if (!FileSystem.exists(target)) File.saveBytes(target, bytes);
    }
  }

  // Heaps olmayan dosyaları da önbelleğe alır, yeni dosya ancak böyle görünür.
  public static function forgetMissingFiles() {
    var local = Std.downcast(hxd.Res.loader.fs, hxd.fs.LocalFileSystem);
    if (local != null) local.clearCache();
  }

  // Arazi modelleri Dünya panelinden alınır, model olarak içe aktarılmaz.
  function collect(directory : String, found : Array<String>) {
    if (!FileSystem.exists(directory) || directory == TerrainModelSource.DIRECTORY) return;
    for (name in FileSystem.readDirectory(directory)) {
      var path = '$directory/$name';
      if (FileSystem.isDirectory(path)) collect(path, found);
      else if (Path.extension(name).toLowerCase() == "fbx") found.push(path);
    }
  }

  function findFile(directory : String, name : String) : Null<String> {
    var entries = FileSystem.readDirectory(directory);
    for (entry in entries) if (entry.toLowerCase() == name.toLowerCase()) return '$directory/$entry';
    for (entry in entries) {
      var path = '$directory/$entry';
      if (!FileSystem.isDirectory(path)) continue;
      var found = findFile(path, name);
      if (found != null) return found;
    }
    return null;
  }

  function createDirectory(directory : String) {
    if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
  }
}
