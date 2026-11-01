package scene;

import scene.data.SceneData.ComponentData;

// Sahnedeki bir nesne. Dönüş dosyada ve burada derecedir, Heaps'e radyan olarak verilir.
@:allow(scene)
class Entity {
  public var id(default, null) : String;
  public var name : String;
  // Oyunda görünür mü: dosyaya yazılır. Editörde görünürlüğü etkilemez, nesne düzenlenebilir kalır.
  public var active(default, set) = true;
  // Yalnızca editörde, kişiye özel: dosyaya yazılmaz, oyunu etkilemez.
  public var hiddenInEditor(default, set) = false;
  // Yalnızca editörde, kişiye özel: sahnede tıklanamaz, Hierarchy'den seçilebilir.
  public var lockedInEditor = false;
  public var scene(default, null) : SceneInstance;
  public var parent(default, null) : Null<Entity>;
  public var children(default, null) : Array<Entity> = [];
  public var components(default, null) : Array<Component> = [];
  public var object(default, null) : h3d.scene.Object;

  public var x(default, null) = 0.;
  public var y(default, null) = 0.;
  public var z(default, null) = 0.;
  public var rotX(default, null) = 0.;
  public var rotY(default, null) = 0.;
  public var rotZ(default, null) = 0.;
  public var scaleX(default, null) = 1.;
  public var scaleY(default, null) = 1.;
  public var scaleZ(default, null) = 1.;

  // Bu derlemede kayıtlı olmayan bileşenler silinmez, olduğu gibi geri yazılır.
  var unknownComponents : Array<ComponentData> = [];

  function new(scene : SceneInstance, id : String, name : String) {
    this.scene = scene;
    this.id = id;
    this.name = name;
    object = new h3d.scene.Object(scene.root);
  }

  public function setPosition(x : Float, y : Float, z : Float) {
    this.x = x;
    this.y = y;
    this.z = z;
    applyTransform();
  }

  public function setRotation(x : Float, y : Float, z : Float) {
    rotX = x;
    rotY = y;
    rotZ = z;
    applyTransform();
  }

  public function setScale(x : Float, y : Float, z : Float) {
    scaleX = x;
    scaleY = y;
    scaleZ = z;
    applyTransform();
  }

  public function setParent(parent : Null<Entity>) {
    if (this.parent != null) this.parent.children.remove(this);
    this.parent = parent;
    if (parent != null) parent.children.push(this);
    (parent == null ? scene.root : parent.object).addChild(object);
  }

  public function addComponent<T:Component>(component : T, ?index : Int) : T {
    component.entity = this;
    if (index == null) components.push(component);
    else components.insert(index, component);
    if (scene.isReady) scene.createComponent(component);
    return component;
  }

  public function removeComponent(component : Component) {
    components.remove(component);
    scene.destroyComponent(component);
  }

  // Kendisi de sayılır: bir nesne kendi altına taşınamaz.
  // Üst nesneler de sayılır: gizlenen nesnenin alt nesneleri de görünmez.
  public function isShown() {
    var current = this;
    while (current != null) {
      if (!current.isVisibleItself()) return false;
      current = current.parent;
    }
    return true;
  }

  public function isInside(other : Entity) {
    var current = this;
    while (current != null) {
      if (current == other) return true;
      current = current.parent;
    }
    return false;
  }

  public function getComponent<T:Component>(type : Class<T>) : Null<T> {
    for (component in components) {
      var match = Std.downcast(component, type);
      if (match != null) return match;
    }
    return null;
  }

  function applyTransform() {
    object.x = x;
    object.y = y;
    object.z = z;
    object.setRotation(radians(rotX), radians(rotY), radians(rotZ));
    object.scaleX = scaleX;
    object.scaleY = scaleY;
    object.scaleZ = scaleZ;
    for (component in components) component.onEntityMoved();
  }

  function isVisibleItself() {
    return scene.mode == Editor ? !hiddenInEditor : active;
  }

  // Bileşenin nesne dışındaki görselleri (sahne köküne bağlı birimler gibi) kendiliğinden gizlenmez.
  function applyVisibility() {
    object.visible = isVisibleItself();
    for (component in components) syncVisuals(component);
    for (child in children) child.applyVisibility();
  }

  function syncVisuals(component : Component) {
    var shown = isShown();
    for (visual in component.visuals()) visual.visible = shown;
  }

  function set_active(value : Bool) {
    active = value;
    applyVisibility();
    return value;
  }

  function set_hiddenInEditor(value : Bool) {
    hiddenInEditor = value;
    applyVisibility();
    return value;
  }

  static inline function radians(degrees : Float) {
    return degrees * Math.PI / 180;
  }
}
