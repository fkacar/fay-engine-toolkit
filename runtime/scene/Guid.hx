package scene;

// Kalıcı kimlik. Referanslar, prefab override'ları ve hücreler arası bağlantılar buna dayanır.
class Guid {
  static inline var LENGTH = 16;
  static inline var DIGITS = "0123456789abcdef";

  public static function make() : String {
    var id = new StringBuf();
    for (i in 0...LENGTH) id.add(DIGITS.charAt(Std.random(DIGITS.length)));
    return id.toString();
  }
}
