package scene.editor;

import haxe.io.Path;
import scene.editor.ModelTrim.TrimBox;
import sys.FileSystem;
import sys.io.File;

typedef ClipSpec = {name : String, source : String};

// Bir FBX'in içe aktarma ayarları, kaynağın yanındaki <ad>.aktarim.json dosyasında:
// trim: kırpma kutuları, clips: başka FBX'lerden alınıp bu modele eklenen klipler.
// Dosya elle de yazılabilir; editör ve ajan aynı biçimi okur, aynı sırayla yazar.
class ImportSettings {
  public static inline var SUFFIX = ".aktarim.json";
  static var CLIP_NAME = ~/^[a-z0-9_]+$/;

  public var trim : Array<TrimBox> = [];
  public var clips : Array<ClipSpec> = [];

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
    return settings;
  }

  public static function checkClip(clip : Dynamic) : ClipSpec {
    var name : String = clip.name, source : String = clip.source;
    if (name == null || !CLIP_NAME.match(name)) throw 'klip adı küçük harf, rakam ve _ olmalı: ${haxe.Json.stringify(clip)}';
    if (source == null || Path.extension(source).toLowerCase() != "fbx") throw 'klibin kaynağı bir FBX olmalı: ${haxe.Json.stringify(clip)}';
    return {name: name, source: StringTools.replace(source, "\\", "/")};
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
    var lines = [for (clip in clips) '    {"name": ${haxe.Json.stringify(clip.name)}, "source": ${haxe.Json.stringify(clip.source)}}'];
    function list(items : Array<String>) return items.length == 0 ? "[]" : "[\n" + items.join(",\n") + "\n  ]";
    File.saveContent(path(source), '{\n  "trim": ${list(boxes)},\n  "clips": ${list(lines)}\n}\n');
  }
}
