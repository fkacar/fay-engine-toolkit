package scene;

import h2d.Scene.ScaleMode;

// Yüksek DPI (README, Retina ve Windows ölçeği): Heaps gerçek piksel boyutunda çizer, 2D sahneler eski birimlerini
// korur; arayüz ve fare kodu ekran yoğunluğunu bilmek zorunda kalmaz. Mac Retina'da arayüz 2 kat, Windows'ta
// kullanıcının ölçek ayarı kadar (%150 → 1,5) büyür. Oyun arayüz ölçeğini kendisi seçebilir (choice).
class HiDpi {
  // Arayüzün büyütme payı: oyunun seçimi, yoksa ekranın ölçeği. fit'e alt sınır verildiyse sahne o yükseklikten
  // küçük kalmasın diye kısılır.
  public static var density(get, never) : Float;
  // Ekranın ölçeği (işletim sistemi): Mac Retina 2, Windows %150 → 1,5.
  public static var displayScale(get, never) : Float;
  // Pencere noktası başına piksel: Mac Retina 2, Windows 1 (pencere koordinatı zaten piksel).
  public static var pixelDensity(get, never) : Float;
  // Oyunun seçtiği arayüz ölçeği; null ise ekranın ölçeği.
  public static var choice : Null<Float> = null;

  static var scene : Null<h2d.Scene>;
  static var minHeight = 0.;

  static function get_displayScale() : Float {
    return #if hidpi hxd.Window.getInstance().contentScale #else 1 #end;
  }

  static function get_pixelDensity() : Float {
    return #if hidpi hxd.Window.getInstance().pixelDensity #else 1 #end;
  }

  static function get_density() : Float {
    var wanted = choice != null && choice > 0 ? choice : displayScale;
    if (minHeight > 0) {
      var pixels = hxd.Window.getInstance().height;
      wanted = Math.min(wanted, Math.max(1, pixels / minHeight));
    }
    return wanted;
  }

  // SDL açılmadan önce, main içinde: Windows görüntüyü bulanık büyütmesin, pencere gerçek pikselle açılsın.
  // SDL3'te çoğunlukla zaten böyledir; ipucu tanınmazsa zararsız.
  public static function prepare() {
    #if hlsdl
    if (Sys.systemName() == "Windows") sdl.Sdl.setHint("SDL_WINDOWS_DPI_AWARENESS", "permonitorv2");
    #end
  }

  // minHeight: arayüzün sığması gereken en küçük sahne yüksekliği (birim); küçük pencerede ölçek ona göre kısılır.
  public static function fit(s2d : h2d.Scene, minHeight = 0.) {
    #if hidpi
    scene = s2d;
    HiDpi.minHeight = minHeight;
    refresh();
    hxd.Window.getInstance().addResizeEvent(refresh);
    #end
  }

  // Ölçek seçimi değişince (oyunun ayarları) sahne yeniden ölçeklenir.
  public static function refresh() {
    #if hidpi
    if (scene == null) return;
    var value = density;
    scene.scaleMode = ScaleMode.Zoom(value);
    scene.defaultSmooth = value != 1;
    #end
  }
}
