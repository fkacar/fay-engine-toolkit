package scene.tune;

// Optimizasyon motoru (docs/OPTIMIZASYON_PLANI.md): bir modülün ayarları, ölçütleri ve senaryosu.
//   Ayar: aralık ve adım; kilitli ayar (tasarım kararı) aramada değişmez, yalnızca etkisi raporlanır.
//   Ölçüt: kalite ya da performans grubunda; amaç en yüksek, en düşük ya da bant; sert sınır aşılırsa kombinasyon elenir.
//   Senaryo: ayarlar ve tohumla çalışır, ölçüm değerlerini döner. Aynı ayar ve tohum aynı sonucu vermeli.
//   synthetic: izler olsa da bu ayarın ölçütlerini süren senaryo sentetik (örneğin kalabalık izi yok); önerisi raporda
//   yazılır, uygulanmaz.
typedef Tunable = {id : String, title : String, min : Float, max : Float, step : Float, value : Float, ?locked : Bool, ?synthetic : Bool};

enum Goal {
  // Değer büyüdükçe iyi; scale değerinde tam puan.
  Max(scale : Float);
  // Değer küçüldükçe iyi; scale değerinde sıfır puan.
  Min(scale : Float);
  // Bant içinde tam puan; dışında uzaklaştıkça azalır, sıfıra inmez (bir bant genişliği ötede yarım puan),
  // böylece çok uzaktaki iki kombinasyon da ayırt edilir.
  Band(low : Float, high : Float);
  // Puana girmez, yalnızca sınır: aşan kombinasyon geçersiz.
  Limit(?low : Float, ?high : Float);
}

typedef Metric = {id : String, title : String, group : String, goal : Goal, weight : Float, ?unit : String};

class TuneModule {
  public static inline var QUALITY = "kalite";
  public static inline var PERFORMANCE = "performans";

  public var id(default, null) : String;
  public var title(default, null) : String;
  public var tunables(default, null) : Array<Tunable>;
  public var metrics(default, null) : Array<Metric>;
  public var run(default, null) : (Map<String, Float>, Int) -> Map<String, Float>;
  // Bir kombinasyonun tohumları çalışmadan önce, ana iş parçacığında bir kez (örneğin tohumdan bağımsız iz oynatması).
  // İşçi süreç havuzunda her süreç kendi prepare'ini çalıştırır.
  public var prepare : Null<Map<String, Float>->Void>;
  // Eğitim tohumları aramada, doğrulama tohumları yalnızca seçilenin denetiminde (aşırı uyum).
  public var seeds : Array<Int> = [1, 2, 3, 4, 5, 6];
  public var validation : Array<Int> = [101, 102, 103];
  // Senaryonun varsayımları: rapora yazılır.
  public var notes : Array<String> = [];
  // Senaryonun kaynağı: SYNTHETIC (tahmin edilmiş dağılımlar) ya da TRACES (gerçek oyun izleri). Yalnızca sentetik
  // senaryonun önerisi uygulanmaz: motor tahmine uyanı bulur, oyuncuya uyanı değil.
  public var source = SYNTHETIC;

  public static inline var SYNTHETIC = "sentetik";
  public static inline var TRACES = "iz";

  public function new(id : String, title : String, tunables : Array<Tunable>, metrics : Array<Metric>, run : (Map<String, Float>, Int) -> Map<String, Float>) {
    this.id = id;
    this.title = title;
    this.tunables = tunables;
    this.metrics = metrics;
    this.run = run;
  }

  // Önerisi uygulanabilir mi: kaynak iz, ayar kilitli değil ve sentetik işaretli değil.
  public function applicable(tunable : Tunable) : Bool {
    return source == TRACES && tunable.locked != true && tunable.synthetic != true;
  }

  // Uygulanacak değerler: uygulanamayan ayar bugünkü değerinde kalır.
  public function applied(config : Map<String, Float>) : Map<String, Float> {
    return [for (tunable in tunables) tunable.id => applicable(tunable) && config.exists(tunable.id) ? config.get(tunable.id) : tunable.value];
  }

  // Kaynak iz olsa da senaryosu sentetik olan, kilitli olmayan ayarlar.
  public function syntheticTunables() : Array<Tunable> {
    return [for (tunable in tunables) if (tunable.locked != true && tunable.synthetic == true) tunable];
  }

  public function current() : Map<String, Float> {
    return [for (tunable in tunables) tunable.id => tunable.value];
  }
}
