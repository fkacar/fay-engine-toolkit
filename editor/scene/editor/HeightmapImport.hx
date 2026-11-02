package scene.editor;

import sys.FileSystem;
import sys.io.File;

// Yükseklik haritası `assets/heightmaps/` altındadır. Resim dünyanın tamamına yayılır, üst kenar
// kuzeydir. Yüklü olmayan hücreler değişmez.
class HeightmapImport {
  public static inline var DIRECTORY = "assets/heightmaps";

  static inline var EXTENSION = ".png";
  static inline var PNG_BIT_DEPTH = 24;

  public static function files() : Array<String> {
    if (!FileSystem.exists(DIRECTORY)) return [];
    var names = FileSystem.readDirectory(DIRECTORY).filter(name -> StringTools.endsWith(name.toLowerCase(), EXTENSION));
    names.sort(Reflect.compare);
    return names;
  }

  // Sonuç: 0-1 arası konuma göre yükseklik. Fırça bunu kilitli kenarları gözeterek uygular.
  public static function read(name : String, low : Float, high : Float) : (Float, Float) -> Float {
    var bytes = File.getBytes('$DIRECTORY/$name');
    var image = hxd.res.Any.fromBytes(name, bytes).toImage();
    // Çözücü 8 biti sRGB, 16 biti doğrusal sayar: bit derinliğine uygun biçim veriyi değiştirmez.
    var isDeep = bytes.get(PNG_BIT_DEPTH) == 16;
    var pixels = image.getPixels(isDeep ? hxd.PixelFormat.R16U : hxd.PixelFormat.RGBA);
    var width = pixels.width, height = pixels.height;
    function sample(x : Int, y : Int) {
      if (isDeep) return pixels.bytes.getUInt16((y * width + x) * 2) / 65535;
      return (pixels.getPixel(x, y) >> 16 & 255) / 255;
    }
    return (u, v) -> {
      var x = u * (width - 1), y = (1 - v) * (height - 1);
      var ix = Std.int(Math.min(x, width - 2)), iy = Std.int(Math.min(y, height - 2));
      var fx = x - ix, fy = y - iy;
      var top = sample(ix, iy) * (1 - fx) + sample(ix + 1, iy) * fx;
      var bottom = sample(ix, iy + 1) * (1 - fx) + sample(ix + 1, iy + 1) * fx;
      return low + (top * (1 - fy) + bottom * fy) * (high - low);
    };
  }
}
