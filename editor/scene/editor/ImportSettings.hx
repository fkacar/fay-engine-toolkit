package scene.editor;

import haxe.io.Path;
import scene.editor.ModelTrim.TrimBox;
import sys.FileSystem;
import sys.io.File;

// arms: kollar (köprücükten ele) bu FBX'in klibinin ilk karesinde sabit durur, gövde ve bacaklar source'tan.
// Kütüphanede olmayan silahlı klipler böyle türetilir: silahsız durma + tüfekli koşunun kol duruşu.
typedef ClipSpec = {name : String, source : String, ?arms : String};

// Takma noktası: silah, kalkan, çanta gibi ayrı modellerin takıldığı yer. Bir eklemde (iskeletsiz
// modelde joint boş: modelin kendisi) konum ve dönüş. Eksenler karakterde X ileri, Y sağ, Z yukarı (bağlama pozunda);
// konum metre ve eklemin dinlenme pozundaki yerine göre, dönüş derece (X, Y, Z eksenleri etrafında).
typedef SocketSpec = {name : String, joint : String, offset : Array<Float>, rotation : Array<Float>};

// Bir FBX'in içe aktarma ayarları, kaynağın yanındaki <ad>.aktarim.json dosyasında:
// trim: kırpma kutuları, clips: başka FBX'lerden alınıp bu modele eklenen klipler,
// sockets: takma noktaları (boşsa iskeletli modelde varsayılanlar kullanılır).
// Dosya elle de yazılabilir; editör ve ajan aynı biçimi okur, aynı sırayla yazar.
class ImportSettings {
  public static inline var SUFFIX = ".aktarim.json";
  static var CLIP_NAME = ~/^[a-z0-9_]+$/;
  static inline var MAX_OFFSET = 5.;

  public var trim : Array<TrimBox> = [];
  public var clips : Array<ClipSpec> = [];
  public var sockets : Array<SocketSpec> = [];

  public function new() {}

  public static function path(source : String) : String {
    return Path.withoutExtension(source) + SUFFIX;
  }

  public static function read(source : String) : ImportSettings {
    var settings = new ImportSettings();
    var file = path(source);
    if (!FileSystem.exists(file)) return settings;
    var raw : Dynamic = haxe.Json.parse(File.getContent(file));
    var boxes : Array<Dynamic> = raw.trim == null ? [] : raw.trim;
    settings.trim = [for (box in boxes) ModelTrim.check(box)];
    var clips : Array<Dynamic> = raw.clips == null ? [] : raw.clips;
    settings.clips = [for (clip in clips) checkClip(clip)];
    var sockets : Array<Dynamic> = raw.sockets == null ? [] : raw.sockets;
    settings.sockets = [for (socket in sockets) checkSocket(socket)];
    return settings;
  }

  public static function checkClip(clip : Dynamic) : ClipSpec {
    var name : String = clip.name, source : String = clip.source;
    if (name == null || !CLIP_NAME.match(name)) throw 'klip adı küçük harf, rakam ve _ olmalı: ${haxe.Json.stringify(clip)}';
    if (source == null || Path.extension(source).toLowerCase() != "fbx") throw 'klibin kaynağı bir FBX olmalı: ${haxe.Json.stringify(clip)}';
    var arms : Null<String> = clip.arms == null || clip.arms == "" ? null : clip.arms;
    if (arms != null && Path.extension(arms).toLowerCase() != "fbx") throw 'klibin kolları bir FBX olmalı: ${haxe.Json.stringify(clip)}';
    var spec : ClipSpec = {name: name, source: StringTools.replace(source, "\\", "/")};
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

  public function write(source : String) {
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
    File.saveContent(path(source), '{\n  "trim": ${list(boxes)},\n  "clips": ${list(lines)},\n  "sockets": ${list(points)}\n}\n');
  }
}
