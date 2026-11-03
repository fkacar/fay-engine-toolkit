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
    var total = count(item) + amount;
    if (total <= 0) items.remove(item);
    else items.set(item, total);
    revision++;
    changed("esya", item, count(item));
  }

  public function flag(name : String) {
    return flags.exists(name) ? flags.get(name) : 0;
  }

  public function setFlag(name : String, value : Int) {
    flags.set(name, value);
    revision++;
    changed("degisken", name, value);
  }

  public function standingWith(faction : String) {
    return standing.exists(faction) ? standing.get(faction) : 0;
  }

  public function changeStanding(faction : String, amount : Int) {
    standing.set(faction, standingWith(faction) + amount);
    revision++;
    changed("iliski", faction, standingWith(faction));
  }
}
