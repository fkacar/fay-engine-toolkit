package scene;

// "Buradan oyna" ile açılan sürecin komut satırı. Editör yazar, oyun okur.
class PlayOptions {
  static inline var PLAY = "--play";
  static inline var CAMERA = "--camera";

  public var scene : String;
  public var camera : Null<Array<Float>>;  // konum ve hedef: x y z x y z

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
    return args;
  }

  public static function parse(args : Array<String>) : Null<PlayOptions> {
    var at = args.indexOf(PLAY);
    if (at < 0 || at + 1 >= args.length) return null;
    var options = new PlayOptions(args[at + 1]);
    var view = args.indexOf(CAMERA);
    if (view >= 0 && view + 6 < args.length) options.camera = [for (i in 1...7) Std.parseFloat(args[view + i])];
    return options;
  }
}
