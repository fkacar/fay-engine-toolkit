package components;

import scene.ColliderComponent;
import scene.ComponentRegistry;
import scene.NavBlockArea;
import scene.WaypointMarker;

// Oyunun ve editörün tanıdığı bileşenler. Yeni bileşen buraya eklenir.
class GameComponents {
  public static function registry() {
    var types = new ComponentRegistry();
    types.register(BoxComponent);
    types.register(ModelComponent);
    types.register(ColliderComponent);
    types.register(WaypointMarker);
    types.register(NavBlockArea);
    return types;
  }
}
