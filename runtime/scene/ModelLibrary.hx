package scene;

// Modeller tek önbellekten gelir: aynı modeli kullanan nesneler geometri ve dokuyu paylaşır,
// her kopya dosyayı yeniden okumaz.
class ModelLibrary {
  static var cache = new h3d.prim.ModelCache();

  public static function load(path : String) : h3d.scene.Object {
    return cache.loadModel(hxd.Res.load(path).toModel());
  }

  // Modelin adlı klibi (içe aktarmada başka FBX'lerden eklenenler dahil). Aynı klip bir kez çözülür;
  // her kullanan createInstance ile kendi kopyasını oynatır.
  public static function animation(path : String, name : String) : h3d.anim.Animation {
    return cache.loadAnimation(hxd.Res.load(path).toModel(), name);
  }

  // Dosya değişince sonraki yükleme diskten okur.
  public static function forget(path : String) {
    @:privateAccess cache.models.remove(path);
    var anims = @:privateAccess cache.anims;
    for (key in [for (key in anims.keys()) key]) if (key == path || StringTools.startsWith(key, path + ":")) anims.remove(key);
  }
}
