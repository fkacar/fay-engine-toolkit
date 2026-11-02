package scene.editor;

import scene.data.ThreeWay;
import scene.data.ThreeWay.MergeOutcome;

// Tablo ve diyalog dosyalarına bağlanma yolu: her biri ayrı dosya, birimleri satır veya düğüm.
typedef StoreAccess = {
  function path(name : String) : String;
  function names() : Array<String>;                     // diskteki ve editördeki bütün adlar
  function base(name : String) : Null<String>;          // editörün diskten son okuduğu
  function setBase(name : String, text : Null<String>) : Void;
  function mine(name : String) : Null<String>;          // editördeki hal, kaydedilecek metin
  function apply(name : String, text : Null<String>) : Void;
  function forget(name : String) : Void;                // o dosyanın geri alma adımları düşer
  function merge(name : String, base : Null<String>, mine : Null<String>, theirs : Null<String>, prefer : Null<String>) : MergeOutcome;
  function canonical(name : String, text : String) : String;
}

// Tablo ve diyaloglar için DiskGuard kuralı: kör yazma yok, dışarıdaki değişiklik ya yeniden
// yüklenir ya da kaydederken birleşir, çakışmada iki hal yedeklenir.
class StoreGuard {
  public static function save(editor : Editor, store : StoreAccess, changed : Map<String, Null<String>>) : Int {
    var count = 0;
    for (name => text in changed) {
      var path = store.path(name);
      var output = text;
      var current = DiskGuard.read(path);
      if (current != store.base(name)) {
        var result = merge(store, name, store.base(name), text, current, null);
        if (result.text == null && result.conflicts.length > 0) {
          editor.diskGuard.backup(path, text, current);
          editor.diskGuard.addConflict(path, result.conflicts, prefer -> resolve(editor, store, name, prefer));
          continue;
        }
        output = result.text;
        if (output != text) replace(store, name, output);
      }
      if (output == null) editor.diskGuard.delete(path);
      else editor.diskGuard.write(path, output);
      store.setBase(name, output);
      count++;
    }
    return count;
  }

  public static function check(editor : Editor, store : StoreAccess) : Array<String> {
    var reloaded = [];
    for (name in store.names()) {
      var path = store.path(name);
      var change = editor.diskGuard.changed(path);
      if (change == null || change.text == store.base(name)) continue;
      var mine = store.mine(name), base = store.base(name);
      if (mine == change.text) {
        store.setBase(name, change.text);
        continue;
      }
      var clean = base == null ? mine == null : mine == store.canonical(name, base);
      if (!clean) {
        editor.diskGuard.pending.set(path, true);
        continue;
      }
      try {
        replace(store, name, change.text);
        store.setBase(name, change.text);
        reloaded.push(path);
      } catch (e : Dynamic) {
        editor.diskGuard.pending.set(path, true);
        editor.show('$path okunamadı: $e', true);
      }
    }
    return reloaded;
  }

  static function resolve(editor : Editor, store : StoreAccess, name : String, prefer : String) {
    var path = store.path(name);
    var current = DiskGuard.read(path);
    var result = merge(store, name, store.base(name), store.mine(name), current, prefer);
    editor.diskGuard.removeConflict(path);
    if (result.text == null) editor.diskGuard.delete(path);
    else editor.diskGuard.write(path, result.text);
    store.setBase(name, result.text);
    replace(store, name, result.text);
  }

  static function merge(store : StoreAccess, name : String, base : Null<String>, mine : Null<String>, theirs : Null<String>, prefer : Null<String>) : MergeOutcome {
    try {
      return store.merge(name, base, mine, theirs, prefer);
    } catch (e : Dynamic) {
      return prefer == null ? {text: null, conflicts: ['okunamadı: $e']} : ThreeWay.whole(base, mine, theirs, prefer, name);
    }
  }

  static function replace(store : StoreAccess, name : String, text : Null<String>) {
    store.apply(name, text);
    store.forget(name);
  }
}
