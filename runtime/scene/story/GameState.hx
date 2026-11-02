package scene.story;

// Oyuncunun ilerlemesi: eşyalar, görev değişkenleri ve fraksiyonlarla ilişki.
class GameState {
  public var items(default, null) = new Map<String, Int>();
  public var flags(default, null) = new Map<String, Int>();
  public var standing(default, null) = new Map<String, Int>();
  // Arayüz her değişiklikte kendini yeniler.
  public var revision(default, null) = 0;

  public function new() {}

  public function count(item : String) {
    return items.exists(item) ? items.get(item) : 0;
  }

  public function give(item : String, amount : Int) {
    var total = count(item) + amount;
    if (total <= 0) items.remove(item);
    else items.set(item, total);
    revision++;
  }

  public function flag(name : String) {
    return flags.exists(name) ? flags.get(name) : 0;
  }

  public function setFlag(name : String, value : Int) {
    flags.set(name, value);
    revision++;
  }

  public function standingWith(faction : String) {
    return standing.exists(faction) ? standing.get(faction) : 0;
  }

  public function changeStanding(faction : String, amount : Int) {
    standing.set(faction, standingWith(faction) + amount);
    revision++;
  }
}
