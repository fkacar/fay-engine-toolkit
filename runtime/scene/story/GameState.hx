package scene.story;

// Oyuncunun ilerlemesi: eşyalar, görev değişkenleri ve fraksiyonlarla ilişki.
class GameState {
  public var items(default, null) = new Map<String, Int>();
  public var flags(default, null) = new Map<String, Int>();
  public var standing(default, null) = new Map<String, Int>();
  // Arayüz her değişiklikte kendini yeniler.
  public var revision(default, null) = 0;
  // İz için: tür (esya, degisken, iliski), ad, yeni değer.
  public var onChange : Null<String->String->Int->Void>;

  // Eşyaların asıl yeri (oyunda ekibin envanterleri): varsa give ona gider, items deponun toplamıdır (depo her
  // değişiklikte sync çağırır). Yoksa (editörde diyalog oynatma, testler) items kendi sayacıdır.
  public var store : Null<ItemStore>;

  // onChange tek kişiliktir (iz onu kullanır); kayıt günlüğü gibi başka dinleyiciler buraya eklenir.
  var watchers : Array<String->String->Int->Void> = [];

  public function new() {}

  public function watch(listener : String->String->Int->Void) {
    watchers.push(listener);
  }

  // Kayıt yüklenince: bütün durum değişir, arayüz yenilenir. Dinleyicilere tek tek haber verilmez.
  public function restore(newItems : Map<String, Int>, newFlags : Map<String, Int>, newStanding : Map<String, Int>) {
    for (pair in [{to: items, from: newItems}, {to: flags, from: newFlags}, {to: standing, from: newStanding}]) {
      pair.to.clear();
      for (key => value in pair.from) pair.to.set(key, value);
    }
    revision++;
  }

  function changed(kind : String, name : String, value : Int) {
    if (onChange != null) onChange(kind, name, value);
    for (listener in watchers) listener(kind, name, value);
  }

  public function count(item : String) {
    return items.exists(item) ? items.get(item) : 0;
  }

  public function give(item : String, amount : Int) {
    if (store != null) {
      store.give(item, amount);
      return;
    }
    var total = count(item) + amount;
    if (total <= 0) items.remove(item);
    else items.set(item, total);
    revision++;
    changed("esya", item, count(item));
  }

  // Deponun toplamları: değişen her eşya için dinleyicilere haber verilir.
  public function sync(totals : Map<String, Int>) {
    var any = false;
    for (name => value in totals) {
      if (count(name) == value) continue;
      if (value <= 0) items.remove(name) else items.set(name, value);
      any = true;
      changed("esya", name, count(name));
    }
    for (name in [for (key in items.keys()) key]) {
      if (totals.exists(name)) continue;
      items.remove(name);
      any = true;
      changed("esya", name, 0);
    }
    if (any) revision++;
  }

  public function flag(name : String) {
    return flags.exists(name) ? flags.get(name) : 0;
  }

  public function setFlag(name : String, value : Int) {
    flags.set(name, value);
    revision++;
    changed("degisken", name, value);
  }

  // Kayıttaki değişim (kaydın biçimi). Oyunun kullandığı ilişki relation'dır.
  public function standingWith(faction : String) {
    return standing.exists(faction) ? standing.get(faction) : 0;
  }

  // İlişkinin oyundaki değeri: oyun bağlar (Story.standingOf: başlangıç ilişkisi ile değişim, ölçekte); bağlı değilse
  // kayıttaki değişim. "iliski" değişikliğinin değeri de budur (olay kaydı, günlük, F3 ve ajan aynı değeri görür).
  public var relationOf : Null<String -> Int>;

  public function relation(faction : String) : Int {
    return relationOf != null ? relationOf(faction) : standingWith(faction);
  }

  public function changeStanding(faction : String, amount : Int) {
    standing.set(faction, standingWith(faction) + amount);
    revision++;
    changed("iliski", faction, relation(faction));
  }
}

// Eşya deposu: verilen (eksi ise alınan) eşyayı yerine koyar, sonra GameState.sync ile toplamları bildirir.
interface ItemStore {
  function give(item : String, amount : Int) : Void;
}
