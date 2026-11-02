package scene.world;

import scene.data.SceneFormat;

typedef WeatherPreset = {
  var id : String;
  var title : String;
  var sun : Float;
  var fogStart : Float;
  var fogEnd : Float;
  var fogColor : Int;
}

// Dünyanın ortamı. Işığın nasıl çizileceği oyuna aittir, burada yalnızca ayarlar durur.
class EnvironmentData {
  public static inline var VERSION = 1;

  public var hour = 8.25;
  public var sun = 1.;
  public var fogStart = 260.;
  public var fogEnd = 1150.;
  public var fogColor = 0xDCC7AA;

  public function new() {}

  public function clone() {
    var copy = new EnvironmentData();
    copy.assign(this);
    return copy;
  }

  public function assign(other : EnvironmentData) {
    hour = other.hour;
    sun = other.sun;
    fogStart = other.fogStart;
    fogEnd = other.fogEnd;
    fogColor = other.fogColor;
  }

  public function applyPreset(preset : WeatherPreset) {
    sun = preset.sun;
    fogStart = preset.fogStart;
    fogEnd = preset.fogEnd;
    fogColor = preset.fogColor;
  }

  public static function read(text : String) : EnvironmentData {
    var raw : Dynamic = haxe.Json.parse(text);
    if (raw.version != VERSION) throw 'Ortam sürümü desteklenmiyor: ${raw.version}';
    var data = new EnvironmentData();
    data.hour = raw.hour;
    data.sun = raw.sun;
    data.fogStart = raw.fogStart;
    data.fogEnd = raw.fogEnd;
    data.fogColor = raw.fogColor;
    return data;
  }

  public function write() : String {
    return '{\n  "version": $VERSION,\n  "hour": ${SceneFormat.number(hour)},\n  "sun": ${SceneFormat.number(sun)},'
      + '\n  "fogStart": ${SceneFormat.number(fogStart)},\n  "fogEnd": ${SceneFormat.number(fogEnd)},\n  "fogColor": $fogColor\n}\n';
  }
}
