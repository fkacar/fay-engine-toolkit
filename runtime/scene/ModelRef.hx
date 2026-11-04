package scene;

// Model başvurusu: oyunun model kataloğundaki satır kimliği ya da dosya yolu. Kimlik `[a-z0-9_]`, yol `/` ya da
// uzantı içerir; ikisi karışmaz. Yol eski içerikte ve modlarda kalabilir, okunmaya devam eder. Oyun kataloğu verir
// (catalog: kimlik → dosya); verilmezse yalnızca yollar çözülür. Heaps'e bağlı değildir, testte yorumlayıcıda çalışır.
class ModelRef {
  public static var catalog : Null<String -> Null<String>>;

  public static function isPath(reference : String) : Bool {
    return reference.indexOf("/") >= 0 || reference.indexOf(".") >= 0;
  }

  // Oyuna girecek dosya (res'e göre yol); boş başvuru ya da katalogda olmayan kimlik için "".
  public static function file(reference : Null<String>) : String {
    if (reference == null || reference == "") return "";
    if (isPath(reference)) return reference;
    var found = catalog == null ? null : catalog(reference);
    return found == null ? "" : found;
  }
}
