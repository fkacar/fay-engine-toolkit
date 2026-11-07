package scene.story;

import scene.Entity;

// Oyunun hikâye tarafı: oyun durumu, açık diyalog ve adlı olaylar. Tetikleyici nesneleri koşul ve
// eylem bileşenleri taşır; olay veya giriş olunca `fire` çağrılır.
class Story {
  public var state(default, null) = new GameState();
  // Fraksiyon ilişkisi: oyun bağlar (başlangıç ilişkisi ve ölçek oyunun tablosunda); bağlı değilse kayıttaki değer.
  public var standingOf : Null<String -> Int>;
  public var dialog(default, null) : Null<DialogRunner>;
  public var messages(default, null) : Array<String> = [];
  // Verilirse her adım kaydedilir: editörden açılan oyun ve görev testi kullanır.
  public var log(default, set) : Null<StoryLog>;
  // Tetikleyicinin koşulları tuttu, eylemleri çalışacak (onFire) ve çalıştı (onFired). Oyunun olay kaydı eylemlerin
  // yaptığı değişiklikleri tetikleyiciye bağlar.
  public var onFire : Null<Entity->Void>;
  public var onFired : Null<Entity->Void>;

  var read : String->Null<String>;
  var listeners = new Map<String, Array<Entity>>();
  var dialogs = new Map<String, Null<Dialog>>();

  public function new(read : String->Null<String>) {
    this.read = read;
  }

  public function listen(event : String, entity : Entity) {
    if (!listeners.exists(event)) listeners.set(event, []);
    if (listeners.get(event).indexOf(entity) < 0) listeners.get(event).push(entity);
  }

  public function unlisten(entity : Entity) {
    for (list in listeners) list.remove(entity);
  }

  public function emit(event : String) {
    var list = listeners.get(event);
    if (log != null) log.add("olay", {name: event, listeners: list == null ? [] : [for (entity in list) entity.name]});
    if (list != null) for (entity in list.copy()) fire(entity);
  }

  // Koşulların hepsi sağlanırsa eylemler çalışır. Sonuç: eylemler çalıştı mı.
  public function fire(entity : Entity) : Bool {
    for (component in entity.components) {
      var condition = Std.downcast(component, TriggerCondition);
      if (condition != null && !condition.passes(this)) {
        if (log != null) log.add("kosul_tutmadi", {trigger: entity.name, id: entity.id, condition: condition.title(), fields: StoryLog.fields(condition)});
        return false;
      }
    }
    if (log != null) log.add("tetikleyici", {trigger: entity.name, id: entity.id, actions: [for (component in entity.components) if (Std.isOfType(component, TriggerAction)) component.title()]});
    if (onFire != null) onFire(entity);
    for (component in entity.components) {
      var action = Std.downcast(component, TriggerAction);
      if (action != null) action.run(this);
    }
    if (onFired != null) onFired(entity);
    return true;
  }

  public function startDialog(id : String) {
    var data = load(id);
    if (log != null) log.add("diyalog", {dialog: id, found: data != null});
    if (data == null) {
      show('Diyalog bulunamadı: $id');
      return;
    }
    dialog = new DialogRunner(data, this);
    if (dialog.finished) dialog = null;
  }

  // Oyuncunun fraksiyonla ilişkisi (diyaloğun İlişki koşulu, tetikleyicinin ilişki koşulu).
  public function standing(faction : String) : Int {
    return standingOf != null ? standingOf(faction) : state.standingWith(faction);
  }

  public function closeDialogIfFinished() {
    if (dialog != null && dialog.finished) dialog = null;
  }

  public function show(message : String) {
    messages.push(message);
    if (log != null) log.add("mesaj", {text: message});
  }

  public function load(id : String) : Null<Dialog> {
    if (!dialogs.exists(id)) {
      var text = read('${Dialog.DIRECTORY}/$id${Dialog.SUFFIX}');
      dialogs.set(id, text == null ? null : Dialog.read(id, text));
    }
    return dialogs.get(id);
  }

  function set_log(value : Null<StoryLog>) {
    state.onChange = value == null ? null : (kind, name, amount) -> value.add(kind, {name: name, value: amount});
    return log = value;
  }
}
