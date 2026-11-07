package scene;

// Kalıcı kimlik. Referanslar, prefab override'ları ve hücreler arası bağlantılar buna dayanır.
// Üreteç her açılışta (ilk kimlikte) zamanla tohumlanır. Std.random bu ikilide her açılışta aynı diziyi veriyordu: ayrı
// oturumlarda aynı kimlikler üretilebiliyordu (7 Kasım 2026: yeni bir bölge, önceki oturumda kurulup geri alınmış bir
// nesnenin kimliğini aldı; kayıtlı nesneyle çakışsaydı yüklü olmayan hücredeki nesnenin kimliği iki kez kullanılırdı).
class Guid {
  static inline var LENGTH = 16;
  static inline var DIGITS = "0123456789abcdef";

  static var random : Null<scene.save.Random>;

  public static function make() : String {
    if (random == null) random = new scene.save.Random(seed());
    var id = new StringBuf();
    for (i in 0...LENGTH) id.add(DIGITS.charAt(random.random(DIGITS.length)));
    return id.toString();
  }

  // Açılışın tohumu: duvar saati (milisaniye), süreç içi yüksek çözünürlüklü sayaç ve platformun rastgelesi karışır.
  static function seed() : Int {
    var now = Date.now().getTime(), stamp = haxe.Timer.stamp();
    var mixed = scene.save.Random.hash(Std.int(now % 1000000000));
    mixed = scene.save.Random.hash(Std.int((stamp * 1000000) % 1000000000), mixed);
    mixed = scene.save.Random.hash(Std.random(0x7FFFFFFF), mixed);
    return mixed == 0 ? 1 : mixed;
  }
}
