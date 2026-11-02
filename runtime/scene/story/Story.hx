package scene.story;

import scene.Entity;

// Oyunun hikâye tarafı: oyun durumu, açık diyalog ve adlı olaylar. Tetikleyici nesneleri koşul ve
// eylem bileşenleri taşır; olay veya giriş olunca `fire` çağrılır.
class Story {
  public var state(default, null) = new GameState();
  public var dialog(default, null) : Null<DialogRunner>;
  public var messages(default, null) : Array<String> = [];

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
    if (list != null) for (entity in list.copy()) fire(entity);
  }

  // Koşulların hepsi sağlanırsa eylemler çalışır. Sonuç: eylemler çalıştı mı.
  public function fire(entity : Entity) : Bool {
    for (component in entity.components) {
      var condition = Std.downcast(component, TriggerCondition);
      if (condition != null && !condition.passes(this)) return false;
    }
    for (component in entity.components) {
      var action = Std.downcast(component, TriggerAction);
      if (action != null) action.run(this);
    }
    return true;
  }

  public function startDialog(id : String) {
    var data = load(id);
    if (data == null) {
      show('Diyalog bulunamadı: $id');
      return;
    }
    dialog = new DialogRunner(data, this);
    if (dialog.finished) dialog = null;
  }

  public function closeDialogIfFinished() {
    if (dialog != null && dialog.finished) dialog = null;
  }

  public function show(message : String) {
    messages.push(message);
  }

  public function load(id : String) : Null<Dialog> {
    if (!dialogs.exists(id)) {
      var text = read('${Dialog.DIRECTORY}/$id${Dialog.SUFFIX}');
      dialogs.set(id, text == null ? null : Dialog.read(id, text));
    }
    return dialogs.get(id);
  }
}
