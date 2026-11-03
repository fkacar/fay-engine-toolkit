package scene.editor;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

typedef ImportResult = {
  var target : Null<String>;
  var problems : Array<String>;
  var ?triangles : Int;
  var ?parts : Int;
  var ?trimmed : Int;
  var ?clips : Array<ModelClips.ClipInfo>;
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
    return sources().filter(needsImport);
  }

  // `assets` altındaki bütün FBX'ler, içe aktarılmış olanlar dahil.
  public function sources() : Array<String> {
    var found = [];
    collect(SOURCE_DIRECTORY, found);
    found.sort(Reflect.compare);
    return found;
  }

  public function targetOf(source : String) {
    var name = SceneDocument.cleanName(Path.withoutDirectory(Path.withoutExtension(source)));
    return '$TARGET_DIRECTORY/$name/$name.hmd';
  }

  // target verilmezse model `res/models` altına yazılır.
  public function run(source : String, ?target : String) : ImportResult {
    var hmd = try convert(source) catch (e : Dynamic) return {target: null, problems: ['$source dönüştürülemedi: $e']};
    var settings = try ImportSettings.read(source) catch (e : Dynamic) return {target: null, problems: ['${ImportSettings.path(source)} okunamadı: $e']};
    var trimmed = ModelTrim.apply(hmd, settings.trim);
    var problems = [];
    var clips = ModelClips.merge(hmd, loadClips(hmd, settings, problems), problems);

    if (target == null) target = targetOf(source);
    createDirectory(Path.directory(target));
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
    // İskeletli modelin oyunda yerleşmesi için boy, birim, kalça, bakış yönü ve klip hızları.
    var info = ModelClips.describe(hmd, clips, settings.sockets);
    if (info != null) File.saveContent(infoPath(target), haxe.Json.stringify(info, null, "  ") + "\n");
    else if (FileSystem.exists(infoPath(target))) FileSystem.deleteFile(infoPath(target));
    forgetMissingFiles();
    // Bu modeli gösteren nesneler önbelleği bırakıp yeniden kurulur.
    var resource = StringTools.startsWith(target, "res/") ? target.substr(4) : target;
    scene.ModelLibrary.forget(resource);
    scene.AssetWatch.changed(resource);
    var triangles = 0;
    for (geometry in hmd.geometries) triangles += Std.int(geometry.indexCount / 3);
    return {target: target, problems: problems, triangles: triangles - trimmed, parts: hmd.geometries.length, trimmed: trimmed, clips: clips};
  }

  public static function infoPath(target : String) : String {
    return Path.withoutExtension(target) + ".model.json";
  }

  // Klibin kendi iskeleti (dinlenme pozu) bir okuyucudan, kareleri başka bir okuyucudan alınır:
  // Heaps loadAnimation'ı aynı okuyucuda ikinci kez çağırınca açıları yeniden radyana çevirir.
  function clipAnimation(source : String, rig : hxd.fmt.hmd.Data) {
    var skeleton = load(source, true, false).hmd;
    var fresh = hxd.fmt.fbx.Parser.parse(File.getBytes(source));
    FbxCurves.sync(fresh);
    var library = new hxd.fmt.fbx.HMDOut(source);
    library.load(fresh);
    // Heaps FBX'i X'te aynalayarak alır; toHMD bunu kendisi yapar, ayrı okuyucuda elle çağrılmalı.
    // Çağrılmazsa klibin dönüşleri aynalanmaz: çok eksenli eklemler (köprücük, baş) ters döner,
    // kollar gövdenin öbür yanına geçer.
    library.leftHandConvert();
    var animation = library.loadAnimation();
    var fixed = ModelClips.retarget(animation, rig, skeleton);
    return {library: library, animation: animation, fixed: fixed};
  }

  function loadClips(rig : hxd.fmt.hmd.Data, settings : ImportSettings, problems : Array<String>) : Array<ModelClips.ClipSource> {
    var found = [];
    for (spec in settings.clips) {
      if (!FileSystem.exists(spec.source)) {
        problems.push('klibin kaynağı yok: ${spec.source}');
        continue;
      }
      if (spec.arms != null && !FileSystem.exists(spec.arms)) {
        problems.push('klibin kol kaynağı yok: ${spec.arms}');
        continue;
      }
      try {
        var clip = clipAnimation(spec.source, rig);
        var library = clip.library, animation = clip.animation, fixed = clip.fixed;
        if (spec.arms != null) {
          var held = ModelClips.holdArms(animation, clipAnimation(spec.arms, rig).animation, rig);
          if (held == 0) problems.push('${spec.name}: ${spec.arms} klibinde kol eklemi bulunamadı');
        }
        // makeAnimation toHMD'nin kurduğu sürüme ve yazma tamponuna dayanır; rigle aynı sürüm yazılır.
        @:privateAccess {
          library.d = new hxd.fmt.hmd.Data();
          library.d.version = rig.version;
          library.dataOut = new haxe.io.BytesOutput();
        }
        var data = new hxd.fmt.hmd.Data();
        data.animations = [@:privateAccess library.makeAnimation(animation)];
        data.data = @:privateAccess library.dataOut.getBytes();
        found.push({spec: spec, hmd: data, animation: animation, retargeted: fixed});
      } catch (e : Dynamic) problems.push('${spec.source} klibi okunamadı: $e');
    }
    return found;
  }

  // Ajan için: dönüştürür ama yazmaz. Sınırlar, iskelet, klipler, kırpma ayarı ve taban haritası.
  public function inspect(source : String, ?floorFraction : Float) : Dynamic {
    var hmd = convert(source);
    var settings = ImportSettings.read(source);
    var boxes = settings.trim;
    var before = ModelTrim.floorMap(hmd, floorFraction);
    var trimmed = ModelTrim.apply(hmd, boxes);
    var problems = [];
    var clips = ModelClips.merge(hmd, loadClips(hmd, settings, problems), problems);
    var triangles = 0;
    for (geometry in hmd.geometries) triangles += Std.int(geometry.indexCount / 3);
    return {
      source: source,
      bounds: ModelTrim.bounds(hmd),
      triangles: triangles - trimmed,
      joints: [for (model in hmd.models) if (model.skin != null) for (joint in model.skin.joints) joint.name],
      clips: [for (anim in hmd.animations) {name: anim.name, frames: anim.frames, seconds: Math.round(anim.frames / anim.sampling * 100) / 100, loop: anim.loop}],
      settings: ImportSettings.path(source),
      clipSources: settings.clips,
      character: ModelClips.describe(hmd, clips, settings.sockets),
      sockets: settings.sockets,
      problems: problems,
      trim: {boxes: boxes, trimmed: trimmed},
      floor: boxes.length == 0 ? before : ({before: before, after: ModelTrim.floorMap(hmd, floorFraction)} : Dynamic),
    };
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
    if (!FileSystem.exists(target)) return true;
    var built = FileSystem.stat(target).mtime.getTime();
    function newer(path : String) return FileSystem.exists(path) && FileSystem.stat(path).mtime.getTime() > built;
    if (newer(source) || newer(ImportSettings.path(source))) return true;
    var clips = try ImportSettings.read(source).clips catch (e : Dynamic) [];
    return Lambda.exists(clips, clip -> newer(clip.source) || (clip.arms != null && newer(clip.arms)));
  }

  function convert(source : String) {
    return load(source, true).hmd;
  }

  // Klip kaynağı geometrisiz okunur: modelin kopyası res'e girmez, yalnızca animasyon alınır.
  function load(source : String, includeGeometry : Bool, unpack = true) {
    var root = hxd.fmt.fbx.Parser.parse(File.getBytes(source));
    if (includeGeometry && unpack) unpackTextures(root, source);
    FbxCurves.sync(root);
    var out = new hxd.fmt.fbx.HMDOut(source);
    out.load(root);
    return {out: out, hmd: out.toHMD(null, includeGeometry)};
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
