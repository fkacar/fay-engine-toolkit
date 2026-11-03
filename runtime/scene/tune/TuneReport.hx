package scene.tune;

import scene.tune.TuneModule;
import scene.tune.Tuner;

// Ayar raporu (docs/ayarlar/<modül>.md): seçilen değerler ve öncekiler, ölçümler (eğitim ve doğrulama tohumları),
// puan, kalite ve performans sınırı, kilitli ayarların etkisi, senaryonun varsayımları.
class TuneReport {
  public static function write(tuner : Tuner, result : SearchResult, date : String) : String {
    var module = tuner.module;
    var best = result.best, base = result.baseline;
    var bestCheck = tuner.evaluate(best.config, module.validation), baseCheck = tuner.evaluate(base.config, module.validation);
    var out = new StringBuf();
    out.add('# Ayar raporu: ${module.title}\n\n');
    if (module.source == TuneModule.SYNTHETIC)
      out.add('> **Kaynak: sentetik senaryo.** Olay sıklıkları ve tehlike durumları tahmin edildi, gerçek oyun izlerinden gelmiyor. Bu rapor öneridir; değerler tabloya uygulanmaz (docs/OPTIMIZASYON_PLANI.md, Gerçek veri).\n\n');
    else out.add('> Kaynak: gerçek oyun izleri.\n\n');
    out.add('Optimizasyon motoru (docs/OPTIMIZASYON_PLANI.md). Üretildi: $date. Yöntem: ${result.method}; ${result.evaluated} kombinasyon denendi. ');
    out.add('Eğitim tohumları ${module.seeds.join(", ")}, doğrulama tohumları ${module.validation.join(", ")}.');
    if (result.rejected > 0) out.add(' Eğitimde daha yüksek puanlı ${result.rejected} aday doğrulama tohumlarında sert sınırı aştığı için seçilmedi (aşırı uyum).');
    if (!bestCheck.valid) out.add(' **Uyarı:** önerilen kombinasyon doğrulamada sert sınırı aşıyor; daha fazla bütçe ya da tohum gerekli.');
    out.add('\n\n');
    out.add('| | Önceki | Önerilen |\n| --- | --- | --- |\n');
    out.add('| Puan (eğitim) | ${pct(base.score)} | ${pct(best.score)} |\n');
    out.add('| Puan (doğrulama) | ${pct(baseCheck.score)} | ${pct(bestCheck.score)} |\n');
    out.add('| Kalite / performans | ${pct(base.quality)} / ${pct(base.performance)} | ${pct(best.quality)} / ${pct(best.performance)} |\n');
    out.add('| Sert sınırlar | ${base.valid ? "tutuyor" : "aşılıyor: " + base.violations.slice(0, 3).join("; ")} | ${best.valid ? "tutuyor" : "aşılıyor: " + best.violations.slice(0, 3).join("; ")} |\n\n');
    out.add('## Ayarlar\n\n| Ayar | Önceki | Önerilen | Aralık, adım |\n| --- | --- | --- | --- |\n');
    for (tunable in module.tunables) {
      var before = base.config.get(tunable.id), after = best.config.get(tunable.id);
      var mark = tunable.locked == true ? " (kilitli)" : before != after ? " **değişti**" : "";
      out.add('| ${tunable.title} (`${tunable.id}`) | $before | $after$mark | ${tunable.min}–${tunable.max}, ${tunable.step} |\n');
    }
    out.add('\n## Ölçütler\n\n| Ölçüt | Grup | Hedef | Önceki | Önerilen | Önerilen, doğrulama |\n| --- | --- | --- | --- | --- | --- |\n');
    for (metric in module.metrics)
      out.add('| ${metric.title} | ${metric.group} | ${goalText(metric)} | ${num(base.values.get(metric.id))} | ${num(best.values.get(metric.id))} | ${num(bestCheck.values.get(metric.id))} |\n');
    out.add('\n## Kalite ve performans sınırı\n\nHiçbir öbürünün ikisinde birden geçemediği geçerli kombinasyonlar (en çok 5):\n\n| Kalite | Performans | Puan | Öncekinden farklı ayarlar |\n| --- | --- | --- | --- |\n');
    for (point in result.front.slice(0, 5)) {
      var diff = [for (t in module.tunables) if (point.config.get(t.id) != base.config.get(t.id)) '${t.id} ${point.config.get(t.id)}'];
      out.add('| ${pct(point.quality)} | ${pct(point.performance)} | ${pct(point.score)} | ${diff.length == 0 ? "-" : diff.join(", ")} |\n');
    }
    var locked = module.tunables.filter(t -> t.locked == true);
    if (locked.length > 0) {
      out.add('\n## Kilitli ayarların etkisi\n\nKilitli ayar aramada değişmez. Önerilen kombinasyonda bir adım oynatılsaydı:\n\n| Ayar | Değer | Puan | Değişen ölçütler |\n| --- | --- | --- | --- |\n');
      for (tunable in locked)
        for (direction in [-1, 1]) {
          var value = best.config.get(tunable.id) + direction * tunable.step;
          if (value < tunable.min - 1e-9 || value > tunable.max + 1e-9) continue;
          var config = best.config.copy();
          config.set(tunable.id, value);
          var other = tuner.evaluate(config);
          var changed = [for (m in module.metrics) if (Math.abs(other.values.get(m.id) - best.values.get(m.id)) > 1e-6) '${m.title} ${num(best.values.get(m.id))} → ${num(other.values.get(m.id))}'];
          out.add('| ${tunable.title} | $value | ${pct(other.score)}${other.valid ? "" : " (geçersiz)"} | ${changed.length == 0 ? "-" : changed.join("; ")} |\n');
        }
    }
    if (module.notes.length > 0) {
      out.add('\n## Senaryonun varsayımları\n\n');
      for (note in module.notes) out.add('- $note\n');
    }
    return out.toString();
  }

  static function goalText(metric : Metric) : String {
    return switch (metric.goal) {
      case Max(scale): 'en yüksek (tam puan $scale${unit(metric)})';
      case Min(scale): 'en düşük (sıfır puan $scale${unit(metric)})';
      case Band(low, high): '$low–$high${unit(metric)}';
      case Limit(low, high): 'sert sınır: ${low != null ? "en az " + low : ""}${low != null && high != null ? ", " : ""}${high != null ? "en çok " + high : ""}${unit(metric)}';
    };
  }

  static function unit(metric : Metric) : String {
    return metric.unit == null ? "" : ' ${metric.unit}';
  }

  static function pct(value : Float) : String {
    return '%${Math.round(value * 1000) / 10}';
  }

  static function num(value : Null<Float>) : String {
    return value == null ? "-" : Std.string(Math.round(value * 100) / 100);
  }
}
