package scene;

// Heaps bir dosyaya tek geri çağrı bağlayabilir. Aynı modeli kullanan her nesne
// yenilensin diye dinleyiciler burada toplanır. Gömülü kaynaklarda etkisizdir.
class AssetWatch {
  static var listeners = new Map<String, Array<Void->Void>>();

  public static function add(path : String, listener : Void->Void) {
    var list = listeners.get(path);
    if (list == null) {
      list = [];
      listeners.set(path, list);
      hxd.Res.load(path).watch(() -> notify(path));
    }
    list.push(listener);
  }

  public static function remove(path : String, listener : Void->Void) {
    var list = listeners.get(path);
    if (list == null) return;
    list.remove(listener);
    if (list.length > 0) return;
    listeners.remove(path);
    hxd.Res.load(path).watch(null);
  }

  // Editör bir dosyayı kendisi yazınca (model içe aktarma) dinleyiciler hemen haberdar edilir: Heaps'in
  // izlemesi birkaç kare sonra gelir, o arada önbellekteki eski başlık yeni dosyayı yanlış okur.
  public static function changed(path : String) {
    if (listeners.exists(path)) notify(path);
  }

  static function notify(path : String) {
    for (listener in listeners.get(path).copy()) listener();
  }
}
