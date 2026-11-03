package scene.tune;

import scene.tune.TuneModule;

typedef Evaluation = {
  config : Map<String, Float>,
  // Ölçüm değerleri tohumların ortalaması; worst: en kötü tohumun puanı.
  values : Map<String, Float>,
  score : Float,
  mean : Float,
  worst : Float,
  quality : Float,
  performance : Float,
  valid : Bool,
  violations : Array<String>,
};

typedef SearchResult = {
  baseline : Evaluation,
  best : Evaluation,
  // Eğitimde daha yüksek puanlı olup doğrulama tohumlarında sert sınırı aşan adaylar (aşırı uyum), atlandı.
  rejected : Int,
  method : String,
  space : Float,
  evaluated : Int,
  // Kalite ve performans arasında hiçbir öbürünün ikisinde birden geçemediği geçerli kombinasyonlar.
  front : Array<Evaluation>,
};

// Arama (docs/OPTIMIZASYON_PLANI.md): uzay bütçeye sığıyorsa kaba kuvvet (bütün ızgara); sığmıyorsa rastgele
// örnekleme ve en iyilerin çevresinde yerel iyileştirme (her ayarı bir adım oynatmak). Önbellek: aynı kombinasyon iki
// kez çalışmaz. Puan tohumların ortalamasının ve en kötüsünün karışımı; sert sınırı aşan kombinasyon geçersiz.
class Tuner {
  static inline var MEAN_SHARE = 0.7;
  static inline var VALIDATION_CANDIDATES = 20;

  public var module(default, null) : TuneModule;
  // Tohumları başka yerde çalıştırmak için (örneğin işçi süreç havuzu): kombinasyon ve tohumlar verilir, tohum
  // sırasıyla ölçümler döner. Yoksa burada sırayla. (İş parçacığı denendi: benzetim çok nesne ürettiği için çöp
  // toplayıcı paylaşılınca yavaşladı; ayrı süreçler kendi belleğiyle ölçeklenir.)
  public var seedRunner : Null<(Map<String, Float>, Array<Int>) -> Array<Map<String, Float>>>;

  var cache = new Map<String, Evaluation>();

  public function new(module : TuneModule) {
    this.module = module;
  }

  public var evaluated(get, never) : Int;

  function get_evaluated() return Lambda.count(cache);

  public function evaluate(config : Map<String, Float>, ?seeds : Array<Int>) : Evaluation {
    var useSeeds = seeds != null ? seeds : module.seeds;
    var key = keyOf(config) + (seeds != null ? "|" + seeds.join(",") : "");
    if (cache.exists(key)) return cache.get(key);
    var sums = new Map<String, Float>();
    var scores = [], qualities = [], performances = [], violations = [];
    var runs = runSeeds(config, useSeeds);
    for (s in 0...useSeeds.length) {
      var seed = useSeeds[s], values = runs[s];
      for (metric in module.metrics) {
        var value = values.exists(metric.id) ? values.get(metric.id) : 0;
        sums.set(metric.id, (sums.exists(metric.id) ? sums.get(metric.id) : 0) + value);
        switch (metric.goal) {
          case Limit(low, high):
            if ((low != null && value < low) || (high != null && value > high)) violations.push('${metric.title}: $value (tohum $seed)');
          default:
        }
      }
      scores.push(scoreOf(values, null));
      qualities.push(scoreOf(values, TuneModule.QUALITY));
      performances.push(scoreOf(values, TuneModule.PERFORMANCE));
    }
    var mean = average(scores), worst = Lambda.fold(scores, Math.min, Math.POSITIVE_INFINITY);
    var evaluation : Evaluation = {
      config: config.copy(), values: [for (id => sum in sums) id => sum / useSeeds.length],
      mean: mean, worst: worst, score: MEAN_SHARE * mean + (1 - MEAN_SHARE) * worst,
      quality: average(qualities), performance: average(performances), valid: violations.length == 0, violations: violations,
    };
    if (seeds == null) cache.set(key, evaluation);
    return evaluation;
  }

  function runSeeds(config : Map<String, Float>, seeds : Array<Int>) : Array<Map<String, Float>> {
    if (seedRunner != null) return seedRunner(config, seeds);
    if (module.prepare != null) module.prepare(config);
    return [for (seed in seeds) module.run(config, seed)];
  }

  // Ağırlıklı puan, 0..1. group verilirse yalnızca o gruptaki ölçütler (grup yoksa 1).
  public function scoreOf(values : Map<String, Float>, group : Null<String>) : Float {
    var total = 0., weights = 0.;
    for (metric in module.metrics) {
      if (group != null && metric.group != group) continue;
      var value = values.exists(metric.id) ? values.get(metric.id) : 0;
      var utility = switch (metric.goal) {
        case Max(scale): clamp(value / scale);
        case Min(scale): clamp(1 - value / scale);
        case Band(low, high):
          var width = Math.max(high - low, 1e-9), away = value < low ? low - value : value > high ? value - high : 0;
          width / (width + away);
        case Limit(_, _): continue;
      };
      total += utility * metric.weight;
      weights += metric.weight;
    }
    return weights == 0 ? 1 : total / weights;
  }

  public function search(budget : Int, seed = 7) : SearchResult {
    var baseline = evaluate(module.current());
    var free = module.tunables.filter(t -> t.locked != true);
    var space = 1.;
    for (tunable in free) space *= countOf(tunable);
    var method = "";
    if (space <= budget) {
      method = 'kaba kuvvet (${Std.int(space)} kombinasyon)';
      grid(free, 0, module.current());
    } else {
      method = 'rastgele örnekleme ve yerel iyileştirme (uzay ${formatSpace(space)})';
      var random = new scene.save.Random(seed);
      var samples = Std.int(budget * 0.4);
      for (_ in 0...samples) {
        var config = module.current();
        for (tunable in free) config.set(tunable.id, valueAt(tunable, random.random(countOf(tunable))));
        evaluate(config);
      }
      var starts = ranked().slice(0, 3);
      for (start in starts) refine(start, free, budget);
    }
    // Seçim: eğitimde en iyiler arasından doğrulama tohumlarında da sert sınırı tutan ilk aday.
    var all = ranked(), best = baseline, rejected = 0;
    for (candidate in all.slice(0, VALIDATION_CANDIDATES)) {
      if (!candidate.valid) break;
      if (evaluate(candidate.config, module.validation).valid) {
        best = candidate;
        break;
      }
      rejected++;
    }
    return {baseline: baseline, best: best, rejected: rejected, method: method, space: space, evaluated: evaluated, front: front()};
  }

  // Yerel iyileştirme: her ayarı bir adım aşağı ve yukarı dener, iyileşme olunca oradan sürer.
  function refine(start : Evaluation, free : Array<Tunable>, budget : Int) {
    var current = start;
    var improved = true;
    while (improved && evaluated < budget) {
      improved = false;
      for (tunable in free)
        for (direction in [-1, 1]) {
          if (evaluated >= budget) return;
          var next = current.config.copy();
          var value = next.get(tunable.id) + direction * tunable.step;
          if (value < tunable.min - 1e-9 || value > tunable.max + 1e-9) continue;
          next.set(tunable.id, round(value, tunable.step));
          var candidate = evaluate(next);
          if (better(candidate, current)) {
            current = candidate;
            improved = true;
          }
        }
    }
  }

  function grid(free : Array<Tunable>, index : Int, config : Map<String, Float>) {
    if (index == free.length) {
      evaluate(config);
      return;
    }
    var tunable = free[index];
    for (i in 0...countOf(tunable)) {
      config.set(tunable.id, valueAt(tunable, i));
      grid(free, index + 1, config);
    }
  }

  // Geçerliler önce, sonra puan; eşitlikte anahtar sırası (her seferinde aynı sonuç).
  public function ranked() : Array<Evaluation> {
    var all = [for (evaluation in cache) evaluation];
    all.sort((a, b) -> better(a, b) ? -1 : better(b, a) ? 1 : (keyOf(a.config) < keyOf(b.config) ? -1 : 1));
    return all;
  }

  static function better(a : Evaluation, b : Evaluation) : Bool {
    if (a.valid != b.valid) return a.valid;
    return a.score > b.score + 1e-12;
  }

  function front() : Array<Evaluation> {
    var valid = [for (evaluation in cache) if (evaluation.valid) evaluation];
    var result = valid.filter(a -> !Lambda.exists(valid, b -> b != a && b.quality >= a.quality && b.performance >= a.performance
      && (b.quality > a.quality || b.performance > a.performance)));
    result.sort((a, b) -> a.quality > b.quality ? -1 : a.quality < b.quality ? 1 : 0);
    return result;
  }

  public static function countOf(tunable : Tunable) : Int {
    return Std.int(Math.floor((tunable.max - tunable.min) / tunable.step + 1e-9)) + 1;
  }

  public static function valueAt(tunable : Tunable, index : Int) : Float {
    return round(tunable.min + index * tunable.step, tunable.step);
  }

  static function round(value : Float, step : Float) : Float {
    var digits = step >= 1 ? 0 : Math.ceil(-Math.log(step) / Math.log(10) + 1e-9);
    var scale = Math.pow(10, digits);
    return Math.round(value * scale) / scale;
  }

  public function keyOf(config : Map<String, Float>) : String {
    return [for (tunable in module.tunables) '${tunable.id}=${config.get(tunable.id)}'].join(";");
  }

  static function average(values : Array<Float>) : Float {
    return values.length == 0 ? 0 : Lambda.fold(values, (a, b) -> a + b, 0.) / values.length;
  }

  static function clamp(value : Float) : Float {
    return value < 0 ? 0 : value > 1 ? 1 : value;
  }

  static function formatSpace(space : Float) : String {
    return space > 1e6 ? '~10^${Math.round(Math.log(space) / Math.log(10))}' : Std.string(Std.int(space));
  }
}
