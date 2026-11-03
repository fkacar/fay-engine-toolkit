package scene.save;

// Kayıt biçimi göçleri (docs/KAYIT_PLANI.md, Sürümler). Her adım bir sürümden bir sonrakine geçen küçük bir
// işlevdir; oyun kendi adımlarını ekler. Bölümler ayrıştırılmış JSON olarak gelir (ad → değer), adım onları
// yerinde değiştirir; ikili bölümler (küçük resim) göçe girmez. Adımlar sırayla uygulanır: v1 → v2 → v3.
class Migrations {
  public var latest(default, null) : Int;

  var steps = new Map<Int, {label : String, run : Map<String, Dynamic>->Void}>();

  public function new(latest : Int) {
    this.latest = latest;
  }

  public function add(from : Int, label : String, run : Map<String, Dynamic>->Void) {
    if (from < 1 || from >= latest) throw 'göç adımı $from → ${from + 1}: en son biçim $latest';
    if (steps.exists(from)) throw 'göç adımı $from → ${from + 1} iki kez eklendi';
    steps.set(from, {label: label, run: run});
  }

  // Uygulanan adımlar ("1 → 2: ..."). Kayıt bu oyundan yeniyse ya da bir adım eksikse hata.
  public function run(sections : Map<String, Dynamic>, version : Int) : Array<String> {
    if (version > latest) throw 'kayıt bu oyundan yeni bir sürümle yapılmış (biçim $version)';
    var applied = [];
    for (at in version...latest) {
      var step = steps.get(at);
      if (step == null) throw 'biçim $at → ${at + 1} göçü yok';
      step.run(sections);
      applied.push('$at → ${at + 1}: ${step.label}');
    }
    return applied;
  }
}
