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
  // Bilgi (sorun değil): tahmin edilen tutamak, uygulanan ölçek gibi.
  var ?notes : Array<String>;
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

  // Mock varlıklar (assets/models/mock) res/models/mock altına yazılır: yayından önce tek klasörle kaldırılır.
  public function targetOf(source : String) {
    var name = SceneDocument.cleanName(Path.withoutDirectory(Path.withoutExtension(source)));
    var mock = StringTools.startsWith(StringTools.replace(source, "\\", "/"), '$SOURCE_DIRECTORY/models/mock/');
    return mock ? '$TARGET_DIRECTORY/mock/$name/$name.hmd' : '$TARGET_DIRECTORY/$name/$name.hmd';
  }

  // Heaps'in okuyacağı FBX: GLB, glTF ve OBJ Blender'la çevrilir (BlenderConverter); FBX olduğu gibi, ayarda
  // "blender": true ise o da Blender'dan geçer.
  function fbxOf(source : String, settings : ImportSettings) : String {
    return BlenderConverter.handles(source) || settings.blender == true ? BlenderConverter.convert(source) : source;
  }

  // target verilmezse model `res/models` altına yazılır.
  public function run(source : String, ?target : String) : ImportResult {
    var settings = try ImportSettings.effective(source) catch (e : Dynamic) return {target: null, problems: ['${ImportSettings.path(source)} okunamadı: $e']};
    var fbx = try fbxOf(source, settings) catch (e : Dynamic) return {target: null, problems: ['$source çevrilemedi: $e']};
    // Klipler modelin kendi dosyasından adla seçiliyorsa dosyadaki bütün klipler modele girmez, yalnızca seçilenler.
    var hmd = try load(fbx, true, true, !ownClips(settings, source)).hmd catch (e : Dynamic) return {target: null, problems: ['$source dönüştürülemedi: $e']};
    var trimmed = ModelTrim.apply(hmd, settings.trim);
    var problems = [], notes = [];
    var names = jointNames(hmd, settings, problems);
    var rigid = !Lambda.exists(hmd.models, model -> model.skin != null);
    if (rigid && settings.length != null) {
      var k = RigidModel.scaleTo(hmd, settings.length);
      notes.push('en uzun kenar ${settings.length} m (x${Math.round(k * 1000) / 1000})');
    }
    var clips = ModelClips.merge(hmd, loadClips(hmd, settings, problems, fbx, source, names), problems, names);

    if (target == null) target = targetOf(source);
    createDirectory(Path.directory(target));
    for (material in hmd.materials) {
      material.diffuseTexture = bringTexture(material.diffuseTexture, fbx, target, problems, source);
      material.specularTexture = bringTexture(material.specularTexture, fbx, target, problems, source);
      material.normalMap = bringTexture(material.normalMap, fbx, target, problems, source);
      // Bu haritaların gölgelendiricisi UV'yi temel renk dokusundan alır, o yoksa çizim hata verir.
      // Yalnızca normal map'i olan malzemeler yaygındır: beyaz doku rengi değiştirmez, detay korunur.
      if (material.diffuseTexture == null && (material.normalMap != null || material.specularTexture != null))
        material.diffuseTexture = whiteTexture(target);
    }

    var out = new haxe.io.BytesOutput();
    new hxd.fmt.hmd.Writer(out).write(hmd);
    File.saveBytes(target, out.getBytes());
    // İskeletli modelin oyunda yerleşmesi için boy, birim, kalça, bakış yönü ve klip hızları.
    var sockets = settings.sockets;
    if (rigid && settings.grip == true && !Lambda.exists(sockets, socket -> socket.name == GripEstimate.GRIP)) {
      var grip = GripEstimate.estimate(RigidModel.points(hmd));
      if (grip != null) {
        sockets = sockets.concat([grip]);
        notes.push('tutamak tahmin edildi: ${haxe.Json.stringify(grip.offset)}');
      } else problems.push("tutamak tahmin edilemedi; ayar dosyasında elle verin");
    }
    var info = ModelClips.describe(hmd, clips, sockets, names);
    // Kaplamalar modelin yanına; adları bilgi dosyasına (çeşitleme birini seçer).
    var skins = [for (file in ImportSettings.skinFiles(source, settings.skins)) {
      var name = Path.withoutDirectory(file);
      File.copy(file, '${Path.directory(target)}/$name');
      name;
    }];
    if (settings.skins != null && skins.length == 0) problems.push('kaplama kalıbına uyan dosya yok: ${settings.skins}');
    if (skins.length > 0) {
      if (info == null) info = {};
      Reflect.setField(info, "skins", skins);
      notes.push('${skins.length} kaplama');
    }
    if (info != null) File.saveContent(infoPath(target), haxe.Json.stringify(info, null, "  ") + "\n");
    else if (FileSystem.exists(infoPath(target))) FileSystem.deleteFile(infoPath(target));
    forgetMissingFiles();
    // Bu modeli gösteren nesneler önbelleği bırakıp yeniden kurulur.
    var resource = StringTools.startsWith(target, "res/") ? target.substr(4) : target;
    scene.ModelLibrary.forget(resource);
    scene.AssetWatch.changed(resource);
    var triangles = 0;
    for (geometry in hmd.geometries) triangles += Std.int(geometry.indexCount / 3);
    return {target: target, problems: problems, triangles: triangles - trimmed, parts: hmd.geometries.length, trimmed: trimmed, clips: clips, notes: notes};
  }

  // Ayardaki bir klip modelin kendi dosyasından mı (kaynak boş ya da modelin kendisi)?
  static function ownClips(settings : ImportSettings, source : String) : Bool {
    return Lambda.exists(settings.clips, clip -> clip.source == "" || clip.source == source);
  }

  // Standart eklem adlarının bu iskeletteki karşılığı (scene.JointNames, ayardaki joints önce). İskeletsizde null.
  function jointNames(hmd : hxd.fmt.hmd.Data, settings : ImportSettings, problems : Array<String>) : Null<Map<String, String>> {
    var skin = Lambda.find(hmd.models, model -> model.skin != null);
    if (skin == null) return null;
    var names = scene.JointNames.resolve([for (joint in skin.skin.joints) joint.name], settings.joints);
    var missing = ["Hips", "LeftFoot", "RightFoot", "RightHand"].filter(standard -> !names.exists(standard));
    if (missing.length > 0) problems.push('standart eklemler bulunamadı: ${missing.join(", ")}; ayar dosyasında "joints" ile eşleyin');
    return names;
  }

  public static function infoPath(target : String) : String {
    return Path.withoutExtension(target) + ".model.json";
  }

  // Klibin kendi iskeleti (dinlenme pozu) bir okuyucudan, kareleri başka bir okuyucudan alınır:
  // Heaps loadAnimation'ı aynı okuyucuda ikinci kez çağırınca açıları yeniden radyana çevirir.
  function clipAnimation(source : String, rig : hxd.fmt.hmd.Data, ?take : String, ?skeletons : Map<String, hxd.fmt.hmd.Data>) {
    var skeleton = skeletons == null ? null : skeletons.get(source);
    if (skeleton == null) {
      skeleton = load(source, true, false, false).hmd;
      if (skeletons != null) skeletons.set(source, skeleton);
    }
    var fresh = hxd.fmt.fbx.Parser.parse(File.getBytes(source));
    FbxCurves.sync(fresh);
    var library = new hxd.fmt.fbx.HMDOut(source);
    library.load(fresh);
    // Heaps FBX'i X'te aynalayarak alır; toHMD bunu kendisi yapar, ayrı okuyucuda elle çağrılmalı.
    // Çağrılmazsa klibin dönüşleri aynalanmaz: çok eksenli eklemler (köprücük, baş) ters döner,
    // kollar gövdenin öbür yanına geçer.
    library.leftHandConvert();
    var animation = library.loadAnimation(takeName(library, take, source));
    var fixed = ModelClips.retarget(animation, rig, skeleton);
    return {library: library, animation: animation, fixed: fixed};
  }

  // Dosyadaki klibin tam adı: aynısı ya da "Armature|Walk_Loop" gibi sonundan eşleşen. take yoksa ilk klip (null).
  static function takeName(library : hxd.fmt.fbx.BaseLibrary, take : Null<String>, source : String) : Null<String> {
    if (take == null || take == "") return null;
    var names = library.getAnimationNames();
    for (name in names) if (name == take) return name;
    for (name in names) if (StringTools.endsWith(name, "|" + take)) return name;
    var short = [for (name in names) name.split("|").pop()];
    throw '$source içinde "$take" klibi yok; dosyadakiler: ${short.slice(0, 60).join(", ")}';
  }

  // own: modelin kendi FBX'i (kaynağı boş klipler buradan); model: ayardaki adı (kaynağı model olan klip).
  function loadClips(rig : hxd.fmt.hmd.Data, settings : ImportSettings, problems : Array<String>, ?own : String, ?model : String,
      ?names : Map<String, String>) : Array<ModelClips.ClipSource> {
    var found = [];
    var skeletons = new Map<String, hxd.fmt.hmd.Data>();
    for (spec in settings.clips) {
      var file = spec.source == "" || spec.source == model ? own : spec.source;
      if (file == null || !FileSystem.exists(file)) {
        problems.push('klibin kaynağı yok: ${spec.source == "" ? "(modelin kendisi)" : spec.source}');
        continue;
      }
      if (spec.arms != null && !FileSystem.exists(spec.arms)) {
        problems.push('klibin kol kaynağı yok: ${spec.arms}');
        continue;
      }
      try {
        var clip = clipAnimation(file, rig, spec.take, skeletons);
        var library = clip.library, animation = clip.animation, fixed = clip.fixed;
        if (spec.arms != null) {
          var held = ModelClips.holdArms(animation, clipAnimation(spec.arms, rig, null, skeletons).animation, rig, names);
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
      } catch (e : Dynamic) problems.push('${spec.name}: ${spec.source == "" ? file : spec.source} klibi okunamadı: $e');
    }
    return found;
  }

  // Ajan için: dönüştürür ama yazmaz. Sınırlar, iskelet, klipler, kırpma ayarı ve taban haritası.
  public function inspect(source : String, ?floorFraction : Float) : Dynamic {
    var settings = ImportSettings.effective(source);
    var fbx = fbxOf(source, settings);
    var hmd = load(fbx, true, true, !ownClips(settings, source)).hmd;
    var boxes = settings.trim;
    var before = ModelTrim.floorMap(hmd, floorFraction);
    var trimmed = ModelTrim.apply(hmd, boxes);
    var problems = [];
    var names = jointNames(hmd, settings, problems);
    var clips = ModelClips.merge(hmd, loadClips(hmd, settings, problems, fbx, source, names), problems, names);
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
      character: ModelClips.describe(hmd, clips, settings.sockets, names),
      sockets: settings.sockets,
      length: settings.length,
      grip: settings.grip,
      blender: settings.blender,
      skins: [for (file in ImportSettings.skinFiles(source, settings.skins)) Path.withoutDirectory(file)],
      jointOverrides: scene.JointNames.toData(settings.joints),
      inherited: settings.inherited,
      standardJoints: names == null ? null : scene.JointNames.toData(names),
      takes: takesOf(fbx),
      problems: problems,
      trim: {boxes: boxes, trimmed: trimmed},
      floor: boxes.length == 0 ? before : ({before: before, after: ModelTrim.floorMap(hmd, floorFraction)} : Dynamic),
    };
  }

  // Heaps tek bir dokuyu bulamazsa modelin tamamını yüklemez. Bu yüzden eksik veya
  // desteklenmeyen doku modelden çıkarılır: tasarımcı modeli görür, eksik uyarı olarak kalır.
  // original: Blender'dan geçen modelde asıl kaynak; doku çeviride gömülmediyse onun klasöründe aranır.
  function bringTexture(texture : Null<String>, source : String, target : String, problems : Array<String>, ?original : String) : Null<String> {
    if (texture == null) return null;
    var name = Path.withoutDirectory(StringTools.replace(texture, "\\", "/"));
    if (TEXTURE_TYPES.indexOf(Path.extension(name).toLowerCase()) < 0) {
      problems.push('$source: desteklenmeyen doku modelden çıkarıldı: $name');
      return null;
    }
    var found = findFile(Path.directory(source), name);
    if (found == null && original != null && original != source) found = findFile(Path.directory(original), name);
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
    if (newer(source) || newer(ImportSettings.path(source)) || Lambda.exists(ImportSettings.folderFiles(source), newer)) return true;
    var clips = try ImportSettings.effective(source).clips catch (e : Dynamic) [];
    return Lambda.exists(clips, clip -> (clip.source != "" && newer(clip.source)) || (clip.arms != null && newer(clip.arms)));
  }

  // Kaynağın klip adları (editörün klip seçimi): GLB ya da blender ayarlı FBX gerekiyorsa önce çevrilir.
  public function takesOfSource(source : String) : Array<String> {
    return takesOf(fbxOf(source, ImportSettings.effective(source)));
  }

  // Dosyadaki kliplerin kısa adları (ajan ve editör için; "Armature|Walk_Loop" → "Walk_Loop").
  public function takesOf(fbx : String) : Array<String> {
    var root = hxd.fmt.fbx.Parser.parse(File.getBytes(fbx));
    var stacks = FbxTools.getAll(root, "Objects.AnimationStack");
    return [for (stack in stacks) FbxTools.getName(stack).split("|").pop()];
  }

  // keepAnimations false: dosyadaki klipler okunmaz (iskelet ve geometri yeter; çok klipli dosyada hızlı).
  function load(source : String, includeGeometry : Bool, unpack = true, keepAnimations = true) {
    var root = hxd.fmt.fbx.Parser.parse(File.getBytes(source));
    if (!keepAnimations) for (objects in FbxTools.getAll(root, "Objects")) objects.childs = objects.childs.filter(node -> node.name != "AnimationStack");
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
    // Komut satırından (kaynaklar kurulmadan) içe aktarmada önbellek yok.
    if (hxd.res.Loader.currentInstance == null) return;
    var local = Std.downcast(hxd.Res.loader.fs, hxd.fs.LocalFileSystem);
    if (local != null) local.clearCache();
  }

  // Arazi modelleri Dünya panelinden alınır, model olarak içe aktarılmaz.
  function collect(directory : String, found : Array<String>) {
    if (!FileSystem.exists(directory) || directory == TerrainModelSource.DIRECTORY) return;
    for (name in FileSystem.readDirectory(directory)) {
      var path = '$directory/$name';
      if (FileSystem.isDirectory(path)) collect(path, found);
      else if (Path.extension(name).toLowerCase() == "fbx" || BlenderConverter.handles(name)) found.push(path);
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
