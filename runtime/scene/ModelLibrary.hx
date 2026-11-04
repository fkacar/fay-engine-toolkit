package scene;

// Modeller tek önbellekten gelir: aynı modeli kullanan nesneler geometri ve dokuyu paylaşır,
// her kopya dosyayı yeniden okumaz. Başvuru katalog kimliği ya da dosya yoludur (ModelRef).
class ModelLibrary {
  static var cache = new h3d.prim.ModelCache();

  public static function load(reference : String) : h3d.scene.Object {
    return cache.loadModel(hxd.Res.load(ModelRef.file(reference)).toModel());
  }

  // Başvurunun dosyası oyunda var mı (bilinmeyen kimlik, boş başvuru ya da eksik dosya: hayır).
  public static function exists(reference : String) : Bool {
    var file = ModelRef.file(reference);
    return file != "" && hxd.Res.loader.exists(file);
  }

  // Modelin adlı klibi (içe aktarmada başka FBX'lerden eklenenler dahil). Aynı klip bir kez çözülür;
  // her kullanan createInstance ile kendi kopyasını oynatır.
  public static function animation(reference : String, name : String) : h3d.anim.Animation {
    return cache.loadAnimation(hxd.Res.load(ModelRef.file(reference)).toModel(), name);
  }

  // Dosya değişince sonraki yükleme diskten okur.
  public static function forget(path : String) {
    @:privateAccess cache.models.remove(path);
    var anims = @:privateAccess cache.anims;
    for (key in [for (key in anims.keys()) key]) if (key == path || StringTools.startsWith(key, path + ":")) anims.remove(key);
  }
}
