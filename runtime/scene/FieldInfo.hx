package scene;

enum FieldKind {
  KFloat;
  KInt;
  KBool;
  KString;
}

typedef FieldInfo = {
  var name : String;
  var label : String;
  var kind : FieldKind;
  var ?min : Float;
  var ?max : Float;
}
