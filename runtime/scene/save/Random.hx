package scene.save;

// Tohumlu rastgele sayı üreticisi (docs/KAYIT_PLANI.md, Rastgelelik). Heaps 2.1'in hxd.Rand'ının birebir
// kopyası: bugünkü dünya aynı sayıları üretir, ama Heaps güncellemesi bu sayıları değiştiremez. Kayıt rastgele
// üretilenleri (NPC dağılımı, görünüş, kayalar) saklamaz, aynı tohumdan yeniden üretir. Algoritma, karma işlevleri
// ve sabitler testlerde altın değerlerle kilitlidir; değiştirmek bir kayıt göçü gerektirir.
class Random {
  var seed : Int;
  var seed2 : Int;

  public function new(seed : Int) {
    init(seed);
  }

  public function init(seed : Int) {
    this.seed = seed;
    this.seed2 = hash(seed);
    if (this.seed == 0) this.seed = 1;
    if (this.seed2 == 0) this.seed2 = 1;
  }

  // Murmur3 karışımı (hxd.Rand.hash ile aynı).
  public static function hash(n : Int, seed = 5381) : Int {
    var n : haxe.Int32 = n;
    n *= 0xcc9e2d51;
    n = (n << 15) | (n >>> 17);
    n *= 0x1b873593;
    var h : haxe.Int32 = seed;
    h ^= n;
    h = (h << 13) | (h >>> 19);
    h = h * 5 + 0xe6546b64;
    h ^= h >> 16;
    h *= 0x85ebca6b;
    h ^= h >> 13;
    h *= 0xc2b2ae35;
    h ^= h >> 16;
    return h;
  }

  // Metinden tohum (FNV-1a): kimlikten ve amaçtan akış türetmek için, "<kimlik>:<amaç>".
  public static function textSeed(text : String) : Int {
    var h = 0x811C9DC5;
    for (i in 0...text.length) h = (h ^ StringTools.fastCodeAt(text, i)) * 0x01000193;
    return h & 0x7FFFFFFF;
  }

  // Doğma alanının yerleşim tohumu (ilk sürümden beri: 17, ×31, 24 bit). Değişirse NPC'ler başka yerde doğar.
  public static function layoutSeed(text : String) : Int {
    var value = 17;
    for (i in 0...text.length) value = value * 31 + StringTools.fastCodeAt(text, i);
    return value & 0xFFFFFF;
  }

  // 0 ile n arası tam sayı (n hariç).
  public inline function random(n : Int) : Int {
    return uint() % n;
  }

  // 0 ile 1 arası (1 hariç).
  public inline function rand() : Float {
    return (uint() % 10007) / 10007.0;
  }

  // -scale ile +scale arası.
  public inline function srand(scale = 1.0) : Float {
    return ((int() % 10007) / 10007.0) * scale;
  }

  public function shuffle<T>(a : Array<T>) {
    var len = a.length;
    for (i in 0...len) {
      var x = random(len);
      var y = random(len);
      var tmp = a[x];
      a[x] = a[y];
      a[y] = tmp;
    }
  }

  // Kayıt için: üreticinin o anki durumu; setState aynı noktadan sürdürür.
  public function state() : Array<Int> {
    return [seed, seed2];
  }

  public function setState(value : Array<Int>) {
    seed = value[0];
    seed2 = value[1];
  }

  // İki Marsaglia MWC üretecinin birleşimi.
  inline function int() : Int {
    seed = 36969 * (seed & 0xFFFF) + (seed >> 16);
    seed2 = 18000 * (seed2 & 0xFFFF) + (seed2 >> 16);
    return ((seed << 16) + seed2) #if js | 0 #end;
  }

  inline function uint() : Int {
    return int() & 0x3FFFFFFF;
  }
}
