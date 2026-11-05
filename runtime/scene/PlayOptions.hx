package scene;

// "Buradan oyna" ile açılan sürecin komut satırı. Editör yazar, oyun okur.
class PlayOptions {
  static inline var PLAY = "--play";
  static inline var CAMERA = "--camera";
  static inline var SAVE = "--save";
  static inline var HOUR = "--hour";

  public var scene : String;
  public var camera : Null<Array<Float>>;  // konum ve hedef: x y z x y z
  // Kayıttan oyna: oyun bu kayıt dosyasıyla açılır (hata ayıklama kopyasına yazar, asıl dosyaya dokunmaz).
  public var save : Null<String>;
  // Yeni seferin başlangıç saati (0–24); yoksa ortamın saati. Kayıttan açılınca kaydın saati geçerlidir.
  public var hour : Null<Float>;

  public function new(scene : String, ?camera : Array<Float>) {
    this.scene = scene;
    this.camera = camera;
  }

  public function toArgs() : Array<String> {
    var args = [PLAY, scene];
    if (camera != null) {
      args.push(CAMERA);
      for (value in camera) args.push(Std.string(value));
    }
    if (save != null) {
      args.push(SAVE);
      args.push(save);
    }
    if (hour != null) {
      args.push(HOUR);
      args.push(Std.string(hour));
    }
    return args;
  }

  public static function parse(args : Array<String>) : Null<PlayOptions> {
    var at = args.indexOf(PLAY);
    if (at < 0 || at + 1 >= args.length) return null;
    var options = new PlayOptions(args[at + 1]);
    var view = args.indexOf(CAMERA);
    if (view >= 0 && view + 6 < args.length) options.camera = [for (i in 1...7) Std.parseFloat(args[view + i])];
    options.save = savePath(args);
    var hour = args.indexOf(HOUR);
    if (hour >= 0 && hour + 1 < args.length) {
      var value = Std.parseFloat(args[hour + 1]);
      if (!Math.isNaN(value)) options.hour = value;
    }
    return options;
  }

  // Dağıtım sürümü de "--save <dosya>" ile açılabilir (Devam et, kayıttan oyna).
  public static function savePath(args : Array<String>) : Null<String> {
    var at = args.indexOf(SAVE);
    return at < 0 || at + 1 >= args.length ? null : args[at + 1];
  }
}
