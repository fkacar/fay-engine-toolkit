package scene;

@:component("waypoint")
class WaypointMarker extends Marker {
  override public function color() : Int {
    return 0xF0D050;
  }

  override public function isPlaceable() {
    return false;
  }

  // Filtre rotayla birlikte çalışır.
  override public function isFiltered() {
    var route = entity.parent == null ? null : Lambda.find(entity.parent.components, c -> Std.isOfType(c, PathMarker));
    return route == null ? super.isFiltered() : Marker.hiddenTypes.exists(route.componentId());
  }

  override public function drawOverlay(overlay : Overlay, selected : Bool) {
    // Rotanın çizgisi yeter, her nokta için ad yazısı kalabalık yapar.
  }
}
