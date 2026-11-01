package components;

import scene.ComponentRegistry;

// Oyunun ve editörün tanıdığı bileşenler. Yeni bileşen buraya eklenir.
class GameComponents {
  public static function registry() {
    var types = new ComponentRegistry();
    types.register(BoxComponent);
    types.register(ModelComponent);
    return types;
  }
}
