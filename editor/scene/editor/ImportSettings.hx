package scene.editor;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

// arms: kollar (köprücükten ele) bu FBX'in klibinin ilk karesinde sabit durur, gövde ve bacaklar source'tan.
// Kütüphanede olmayan silahlı klipler böyle türetilir: silahsız durma + tüfekli koşunun kol duruşu.
// take: kaynaktaki klibin adı (çok klipli dosya); "Armature|Walk_Loop" gibi adlar sonundan da eşleşir. Yoksa ilk klip.
// source boşsa klip modelin kendi dosyasından alınır (take ile).
typedef ClipSpec = {name : String, source : String, ?take : String, ?arms : String};

// Kırpma kutusu (ModelTrim): içinde kalan üçgenler atılır; modelin birimleriyle, Z yukarı.
typedef TrimBox = {min : Array<Float>, max : Array<Float>, ?note : String};

// Takma noktası: silah, kalkan, çanta gibi ayrı modellerin takıldığı yer. Bir eklemde (iskeletsiz
// modelde joint boş: modelin kendisi) konum ve dönüş. Eksenler karakterde X ileri, Y sağ, Z yukarı (bağlama pozunda);
// konum metre ve eklemin dinlenme pozundaki yerine göre, dönüş derece (X, Y, Z eksenleri etrafında).
typedef SocketSpec = {name : String, joint : String, offset : Array<Float>, rotation : Array<Float>};

// Bir modelin (FBX ya da GLB) içe aktarma ayarları, kaynağın yanındaki <ad>.aktarim.json dosyasında:
// trim: kırpma kutuları, clips: bu modele eklenen klipler (başka dosyadan ya da kendi dosyasının adlı klibi),
// sockets: takma noktaları (boşsa iskeletli modelde varsayılanlar), joints: standart eklem adı → iskeletteki ad
// (tanınmayan iskelet için; bkz. scene.JointNames), length: modelin en uzun kenarı metre (iskeletsiz modeller;
// silah paketleri 1 birime sığdırılmış gelir), grip: true ise iskeletsiz modele "tutamak" tahmin edilir (elle verilmemişse),
// blender: true ise FBX önce Blender'dan geçer (başka aracın ölçeğiyle yazılmış dosya; bkz. BlenderConverter),
// skins: modelin kaplamaları, kaynağa göre bir kalıp ("textures/{ad}_skin*.png"; {ad} model dosyasının adı, tek *);
// eşleşenler modelin yanına kopyalanır, oyun çeşitlemede birini seçer.
// Klasör ayarı (klasor.aktarim.json): klasördeki ve alt klasörlerdeki bütün modeller için ortak klipler, takma
// noktaları ve eklem adları; modelin kendi dosyası aynı adlı olanı ezer. Aynı iskeletli bir paket tek dosyayla alınır.
// Dosya elle de yazılabilir; editör ve ajan aynı biçimi okur, aynı sırayla yazar.
class ImportSettings {
  public static inline var SUFFIX = ".aktarim.json";
  public static inline var FOLDER_FILE = "klasor.aktarim.json";
  static inline var SOURCE_ROOT = "assets";
  static var CLIP_NAME = ~/^[a-z0-9_]+$/;
  static inline var MAX_OFFSET = 5.;

  public var trim : Array<TrimBox> = [];
  public var clips : Array<ClipSpec> = [];
  public var sockets : Array<SocketSpec> = [];
  public var joints = new Map<String, String>();
  public var length : Null<Float> = null;
  public var grip : Null<Bool> = null;
  public var blender : Null<Bool> = null;
  public var skins : Null<String> = null;
  // Etkin ayarı oluşturan klasör dosyaları (en uzaktan en yakına); bilgi için.
  public var inherited : Array<String> = [];

  public function new() {}

  public static function path(source : String) : String {
    return Path.withoutExtension(source) + SUFFIX;
  }

  public static function read(source : String) : ImportSettings {
    return readFile(path(source));
  }

  // Modelin kendi ayarı ile üstündeki klasör ayarları birleşik: içe aktarma bunu kullanır. Kırpma yalnızca modelin.
  public static function effective(source : String) : ImportSettings {
    var merged = new ImportSettings();
    for (file in folderFiles(source)) {
      mergeInto(merged, readFile(file));
      merged.inherited.push(file);
    }
    var own = read(source);
    mergeInto(merged, own);
    merged.trim = own.trim;
    return merged;
  }

  // Kaynağın üstündeki klasör ayarları, assets'e kadar; en uzaktan en yakına.
  public static function folderFiles(source : String) : Array<String> {
    var found = [];
    var directory = Path.directory(StringTools.replace(source, "\\", "/"));
    while (directory != "" && directory != ".") {
      var file = '$directory/$FOLDER_FILE';
      if (FileSystem.exists(file)) found.unshift(file);
      if (Path.withoutDirectory(directory) == SOURCE_ROOT) break;
      directory = Path.directory(directory);
    }
    return found;
  }

  static function mergeInto(into : ImportSettings, from : ImportSettings) {
    for (clip in from.clips) {
      into.clips = into.clips.filter(other -> other.name != clip.name);
      into.clips.push(clip);
    }
    for (socket in from.sockets) {
      into.sockets = into.sockets.filter(other -> other.name != socket.name);
      into.sockets.push(socket);
    }
    for (standard => actual in from.joints) into.joints.set(standard, actual);
    if (from.length != null) into.length = from.length;
    if (from.grip != null) into.grip = from.grip;
    if (from.blender != null) into.blender = from.blender;
    if (from.skins != null) into.skins = from.skins;
  }

  public static function readFile(file : String) : ImportSettings {
    var settings = new ImportSettings();
    if (!FileSystem.exists(file)) return settings;
    var raw : Dynamic = haxe.Json.parse(File.getContent(file));
    var boxes : Array<Dynamic> = raw.trim == null ? [] : raw.trim;
    settings.trim = [for (box in boxes) checkBox(box)];
    var clips : Array<Dynamic> = raw.clips == null ? [] : raw.clips;
    settings.clips = [for (clip in clips) checkClip(clip)];
    var sockets : Array<Dynamic> = raw.sockets == null ? [] : raw.sockets;
    settings.sockets = [for (socket in sockets) checkSocket(socket)];
    if (raw.joints != null) for (field in Reflect.fields(raw.joints)) {
      var value : Dynamic = Reflect.field(raw.joints, field);
      if (!Std.isOfType(value, String) || value == "") throw 'eklem eşlemesi ad olmalı: $field';
      settings.joints.set(field, value);
    }
    if (raw.length != null) settings.length = checkLength(raw.length);
    if (raw.grip == true || raw.grip == false) settings.grip = raw.grip;
    if (raw.blender == true || raw.blender == false) settings.blender = raw.blender;
    if (raw.skins != null) settings.skins = checkSkins(raw.skins);
    return settings;
  }

  public static function checkBox(box : Dynamic) : TrimBox {
    var min : Array<Float> = box.min, max : Array<Float> = box.max;
    if (min == null || max == null || min.length != 3 || max.length != 3) throw "kırpma kutusu {min: [x, y, z], max: [x, y, z]} olmalı";
    for (i in 0...3) if (!Std.isOfType(min[i], Float) || !Std.isOfType(max[i], Float) || min[i] > max[i]) throw 'kırpma kutusunda min, max\'tan büyük ya da sayı değil: ${haxe.Json.stringify(box)}';
    return {min: min, max: max, note: box.note};
  }

  // Kaplama kalıbı: kaynağın klasörüne göre, klasörden çıkmaz, dosya adında en çok bir *. Boş metin kaldırır.
  public static function checkSkins(value : Dynamic) : Null<String> {
    if (!Std.isOfType(value, String)) throw 'skins bir kalıp olmalı ("textures/{ad}_skin*.png"): $value';
    var pattern = StringTools.replace((value : String), "\\", "/");
    if (pattern == "") return null;
    if (pattern.indexOf("..") >= 0 || StringTools.startsWith(pattern, "/")) throw 'skins kaynağın klasöründe kalmalı: $pattern';
    if (Path.withoutDirectory(pattern).split("*").length > 2 || Path.directory(pattern).indexOf("*") >= 0) throw 'skins dosya adında en çok bir * içerebilir: $pattern';
    return pattern;
  }

  // Kalıba uyan dosyalar (kaynağın klasörüne göre yol, sıralı).
  public static function skinFiles(source : String, pattern : Null<String>) : Array<String> {
    if (pattern == null) return [];
    var name = Path.withoutExtension(Path.withoutDirectory(source));
    var resolved = StringTools.replace(pattern, "{ad}", name);
    var base = Path.directory(StringTools.replace(source, "\\", "/"));
    var folder = Path.directory(resolved) == "" ? base : '$base/${Path.directory(resolved)}';
    if (!FileSystem.exists(folder) || !FileSystem.isDirectory(folder)) return [];
    var parts = Path.withoutDirectory(resolved).split("*");
    var found = [for (entry in FileSystem.readDirectory(folder))
      if (parts.length == 1 ? entry == parts[0] : StringTools.startsWith(entry, parts[0]) && StringTools.endsWith(entry, parts[1]) && entry.length >= parts[0].length + parts[1].length) '$folder/$entry'];
    found.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return found;
  }

  public static function checkLength(value : Dynamic) : Float {
    var number : Float = Std.isOfType(value, Float) || Std.isOfType(value, Int) ? value : Math.NaN;
    if (!Math.isFinite(number) || number <= 0 || number > 100) throw 'length 0 ile 100 metre arasında olmalı: $value';
    return number;
  }

  public static function checkClip(clip : Dynamic) : ClipSpec {
    var name : String = clip.name, source : String = clip.source == null ? "" : clip.source;
    var take : Null<String> = clip.take == null || clip.take == "" ? null : clip.take;
    if (name == null || !CLIP_NAME.match(name)) throw 'klip adı küçük harf, rakam ve _ olmalı: ${haxe.Json.stringify(clip)}';
    if (source == "" && take == null) throw 'klibin kaynağı ya da modelin kendi dosyasındaki adı (take) olmalı: ${haxe.Json.stringify(clip)}';
    if (source != "" && Path.extension(source).toLowerCase() != "fbx") throw 'klibin kaynağı bir FBX olmalı: ${haxe.Json.stringify(clip)}';
    var arms : Null<String> = clip.arms == null || clip.arms == "" ? null : clip.arms;
    if (arms != null && Path.extension(arms).toLowerCase() != "fbx") throw 'klibin kolları bir FBX olmalı: ${haxe.Json.stringify(clip)}';
    var spec : ClipSpec = {name: name, source: StringTools.replace(source, "\\", "/")};
    if (take != null) spec.take = take;
    if (arms != null) spec.arms = StringTools.replace(arms, "\\", "/");
    return spec;
  }

  public static function checkSocket(socket : Dynamic) : SocketSpec {
    var text = haxe.Json.stringify(socket);
    var name : String = socket.name, joint : Null<String> = socket.joint;
    if (name == null || !CLIP_NAME.match(name)) throw 'takma noktasının adı küçük harf, rakam ve _ olmalı: $text';
    if (joint != null && !Std.isOfType(joint, String)) throw 'takma noktasının eklemi bir ad olmalı: $text';
    function vector(value : Dynamic, label : String, limit : Float) : Array<Float> {
      if (value == null) return [0., 0., 0.];
      var items : Array<Dynamic> = Std.isOfType(value, Array) ? value : null;
      if (items == null || items.length != 3) throw 'takma noktasının $label üç sayı olmalı: $text';
      return [for (item in items) {
        var number : Float = Std.isOfType(item, Float) || Std.isOfType(item, Int) ? item : Math.NaN;
        if (!Math.isFinite(number) || Math.abs(number) > limit) throw 'takma noktasının $label ±$limit içinde sayılar olmalı: $text';
        number;
      }];
    }
    return {name: name, joint: joint == null ? "" : joint, offset: vector(socket.offset, "konumu", MAX_OFFSET), rotation: vector(socket.rotation, "dönüşü", 360)};
  }

  // file verilirse oraya yazar (klasör ayarı: <klasör>/klasor.aktarim.json).
  public function write(source : String, ?file : String) {
    var names = new Map<String, Bool>();
    for (clip in clips) {
      if (names.exists(clip.name)) throw 'aynı adda iki klip: ${clip.name}';
      names.set(clip.name, true);
    }
    var boxes = [for (box in trim) {
      var text = '{"min": ${haxe.Json.stringify(box.min)}, "max": ${haxe.Json.stringify(box.max)}';
      '    ' + text + (box.note == null || box.note == "" ? "" : ', "note": ${haxe.Json.stringify(box.note)}') + "}";
    }];
    var lines = [for (clip in clips) '    {"name": ${haxe.Json.stringify(clip.name)}, "source": ${haxe.Json.stringify(clip.source)}'
      + (clip.take == null || clip.take == "" ? "" : ', "take": ${haxe.Json.stringify(clip.take)}')
      + (clip.arms == null || clip.arms == "" ? "" : ', "arms": ${haxe.Json.stringify(clip.arms)}') + '}'];
    var socketNames = new Map<String, Bool>();
    for (socket in sockets) {
      if (socketNames.exists(socket.name)) throw 'aynı adda iki takma noktası: ${socket.name}';
      socketNames.set(socket.name, true);
    }
    var points = [for (socket in sockets) {
      var spec = checkSocket(socket);
      '    {"name": ${haxe.Json.stringify(spec.name)}, "joint": ${haxe.Json.stringify(spec.joint)}, "offset": ${haxe.Json.stringify(spec.offset)}, "rotation": ${haxe.Json.stringify(spec.rotation)}}';
    }];
    function list(items : Array<String>) return items.length == 0 ? "[]" : "[\n" + items.join(",\n") + "\n  ]";
    // Yeni alanlar yalnızca kullanılınca yazılır: eski dosyalar yeniden yazılınca aynı kalır.
    var extra = "";
    var mapped = [for (standard in scene.JointNames.STANDARD) if (joints.exists(standard)) '    ${haxe.Json.stringify(standard)}: ${haxe.Json.stringify(joints.get(standard))}'];
    if (mapped.length > 0) extra += ',\n  "joints": {\n' + mapped.join(",\n") + "\n  }";
    if (length != null) extra += ',\n  "length": ${checkLength(length)}';
    if (grip != null) extra += ',\n  "grip": $grip';
    if (blender != null) extra += ',\n  "blender": $blender';
    if (skins != null) extra += ',\n  "skins": ${haxe.Json.stringify(checkSkins(skins))}';
    File.saveContent(file == null ? path(source) : file, '{\n  "trim": ${list(boxes)},\n  "clips": ${list(lines)},\n  "sockets": ${list(points)}$extra\n}\n');
  }
}
