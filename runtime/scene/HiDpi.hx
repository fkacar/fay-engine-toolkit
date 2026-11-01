package scene;

import h2d.Scene.ScaleMode;

// Heaps Retina ekranda gerçek piksel boyutunda çizer. 2D sahneler eski birimlerini korur,
// böylece arayüz ve fare kodu ekran yoğunluğunu bilmek zorunda kalmaz.
class HiDpi {
  public static var density(get, never) : Float;

  static function get_density() : Float {
    return #if hidpi hxd.Window.getInstance().pixelDensity #else 1 #end;
  }

  public static function fit(s2d : h2d.Scene) {
    #if hidpi
    function apply() {
      s2d.scaleMode = ScaleMode.Zoom(density);
      s2d.defaultSmooth = density > 1;
    }
    apply();
    hxd.Window.getInstance().addResizeEvent(apply);
    #end
  }
}
