package scene.save;

import haxe.DynamicAccess;

// Oyun olaylarının rastgeleliği (dövüş, ganimet, yapay zekâ): seferin tohumundan adlı akışlar. Her amaç kendi
// akışını kullanır, birine çekiliş eklemek ötekini kaydırmaz. Durumlar kayıtta saklanır: yükleyince aynı akış
// sürer, oyuncunun kaydından hata aynı yoldan yeniden üretilir. Tasarlanmış içerik (dağılım, görünüş) bunu
// kullanmaz; o içerikten tohum alır, her oyuncuda aynıdır.
class RandomStreams {
  public var seed(default, null) : Int;

  var streams = new Map<String, Random>();

  public function new(seed : Int) {
    this.seed = seed;
  }

  public function get(name : String) : Random {
    var stream = streams.get(name);
    if (stream == null) {
      stream = new Random(Random.hash(Random.textSeed(name), seed));
      streams.set(name, stream);
    }
    return stream;
  }

  public function toData() : Dynamic {
    var states : DynamicAccess<Array<Int>> = {};
    var names = [for (name in streams.keys()) name];
    names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    for (name in names) states.set(name, streams.get(name).state());
    return {seed: seed, streams: states};
  }

  public static function fromData(data : Dynamic) : RandomStreams {
    var result = new RandomStreams(data.seed);
    var states : Null<DynamicAccess<Array<Int>>> = data.streams;
    if (states != null) for (name => state in states) result.get(name).setState(state);
    return result;
  }
}
