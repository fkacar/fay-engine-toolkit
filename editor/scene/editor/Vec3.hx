package scene.editor;

// Gizmo hesapları için yalın vektör. Heaps'e bağlı değildir, yorumlayıcıda test edilir.
class Vec3 {
  public var x : Float;
  public var y : Float;
  public var z : Float;

  public inline function new(x = 0., y = 0., z = 0.) {
    this.x = x;
    this.y = y;
    this.z = z;
  }

  public inline function add(o : Vec3) {
    return new Vec3(x + o.x, y + o.y, z + o.z);
  }

  public inline function sub(o : Vec3) {
    return new Vec3(x - o.x, y - o.y, z - o.z);
  }

  public inline function scale(f : Float) {
    return new Vec3(x * f, y * f, z * f);
  }

  public inline function dot(o : Vec3) {
    return x * o.x + y * o.y + z * o.z;
  }

  public inline function cross(o : Vec3) {
    return new Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  }

  public inline function length() {
    return Math.sqrt(dot(this));
  }

  public function normalized() {
    var size = length();
    return size == 0 ? new Vec3() : scale(1 / size);
  }
}
