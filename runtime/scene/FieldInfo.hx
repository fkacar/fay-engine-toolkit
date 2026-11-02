package scene;

enum FieldKind {
  KFloat;
  KInt;
  KBool;
  KString;
  KStringList;
  KFloatList;
}

// Metin alanının anlamı: Inspector uygun girişi gösterir, kayıt doğrulaması buna bakar.
enum FieldHint {
  HNone;
  HAsset;
  HEntity;
  HPrefab;
  HColor;
  HChoice(options : Array<String>);
  HRef(table : String);
  HDialog;
}

typedef FieldInfo = {
  var name : String;
  var label : String;
  var kind : FieldKind;
  var ?min : Float;
  var ?max : Float;
  var ?hint : FieldHint;
}
