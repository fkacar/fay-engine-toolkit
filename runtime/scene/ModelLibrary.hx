package scene;

// Modeller tek önbellekten gelir: aynı modeli kullanan nesneler geometri ve dokuyu paylaşır,
// her kopya dosyayı yeniden okumaz.
class ModelLibrary {
  static var cache = new h3d.prim.ModelCache();

  public static function load(path : String) : h3d.scene.Object {
    return cache.loadModel(hxd.Res.load(path).toModel());
  }

  // Dosya değişince sonraki yükleme diskten okur.
  public static function forget(path : String) {
    @:privateAccess cache.models.remove(path);
  }
}
