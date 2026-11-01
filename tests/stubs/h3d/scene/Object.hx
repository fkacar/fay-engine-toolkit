package h3d.scene;

// Heaps yorumlayıcıda derlenmez. Testler yalnızca bu kadarına ihtiyaç duyar;
// gerçek tip kontrolünü HashLink derlemesi yapar.
class Object {
  public var parent : Object;
  public var children : Array<Object> = [];
  public var visible = true;
  public var x = 0.;
  public var y = 0.;
  public var z = 0.;
  public var scaleX = 1.;
  public var scaleY = 1.;
  public var scaleZ = 1.;
  public var rotation = [0., 0., 0.];

  public function new(?parent : Object) {
    if (parent != null) parent.addChild(this);
  }

  public function addChild(child : Object) {
    child.remove();
    child.parent = this;
    children.push(child);
  }

  public function remove() {
    if (parent != null) parent.children.remove(this);
    parent = null;
  }

  public function setRotation(x : Float, y : Float, z : Float) {
    rotation = [x, y, z];
  }
}
