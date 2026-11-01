package components;

import h3d.scene.Mesh;
import scene.Component;

// Örnek bileşen: Inspector'dan boyutu ve rengi değişen bir kutu.
@:component("box")
class BoxComponent extends Component {
  @:editable("Boyut", 0.1, 20) public var size : Float = 2;
  @:editable("Renk") public var color : Int = 0xC9A37A;

  var mesh : Mesh;

  override function onCreate() {
    var prim = new h3d.prim.Cube(size, size, size, true);
    prim.unindex();
    prim.addNormals();
    mesh = new Mesh(prim, entity.object);
    mesh.material.color.setColor(0xFF000000 | color);
  }

  override function onDestroy() {
    mesh.remove();
  }
}
