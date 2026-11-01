package scene;

enum FieldKind {
  KFloat;
  KInt;
  KBool;
  KString;
}

// Metin alanının anlamı: Inspector uygun girişi gösterir, kayıt doğrulaması buna bakar.
enum FieldHint {
  HNone;
  HAsset;
  HEntity;
}

typedef FieldInfo = {
  var name : String;
  var label : String;
  var kind : FieldKind;
  var ?min : Float;
  var ?max : Float;
  var ?hint : FieldHint;
}
