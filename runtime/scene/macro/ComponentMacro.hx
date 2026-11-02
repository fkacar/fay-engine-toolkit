package scene.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;

private typedef Editable = {
  var name : String;
  var label : String;
  var kind : String;
  var min : Null<Float>;
  var max : Null<Float>;
  var hint : Expr;
  var former : Array<String>;
}

// `@:editable` alanlardan Inspector ve kayıt kodunu üretir. Reflection kullanılmaz,
// böylece alanlar DCE ile silinmez ve yazım hataları derlemede yakalanır.
//
//   @:editable var height : Float = 4;
//   @:editable("Yükseklik") var height : Float = 4;
//   @:editable("Yükseklik", 1, 20) var height : Float = 4;
//   @:editable @:formerly("h") var height : Float = 4;
//   @:editable("Model") @:asset var path : String = "";
//   @:editable("Hedef") @:entity var target : String = "";
//   @:editable("Parça") @:prefab var part : String = "";
//   @:editable("Tür") @:choice("kolay", "zor") var kind : String = "kolay";
//   @:editable("Fraksiyon") @:ref("fraksiyonlar") var faction : String = "tarafsiz";
//   @:editable("Renk") @:color var tint : Int = 0xFF8000;
//   @:editable("Etiketler") var tags : Array<String> = [];
class ComponentMacro {
  public static function build() : Array<Field> {
    var fields = Context.getBuildFields();
    addIdentity(fields);
    var editable = [];
    for (field in fields) {
      var meta = field.meta == null ? null : Lambda.find(field.meta, entry -> entry.name == ":editable");
      if (meta != null) editable.push(describe(field, meta));
    }
    if (editable.length == 0) return fields;

    var pos = Context.currentPos();
    var pushes = [for (item in editable) macro list.push({
      name: $v{item.name},
      label: $v{item.label},
      kind: $p{["scene", "FieldInfo", "FieldKind", item.kind]},
      min: $v{item.min},
      max: $v{item.max},
      hint: ${item.hint},
    })];
    var reads = [for (item in editable) {
      var name = item.name;
      {values: [macro $v{name}], expr: macro return this.$name};
    }];
    var writes = [for (item in editable) {
      var name = item.name;
      var names = [name].concat(item.former);
      var assign = switch (item.kind) {
        case "KStringList": macro { var list : Array<Dynamic> = value; this.$name = [for (entry in list) (entry : String)]; };
        case "KFloatList": macro { var list : Array<Dynamic> = value; this.$name = [for (entry in list) (entry : Float)]; };
        default: macro this.$name = value;
      };
      {values: [for (entry in names) macro $v{entry}], expr: macro { $assign; return true; }};
    }];

    fields.push(method("describeFields", [], macro : Array<scene.FieldInfo>, macro {
      var list = super.describeFields();
      $b{pushes};
      return list;
    }, pos));
    fields.push(method("readField", [{name: "name", type: macro : String}], macro : Dynamic,
      {expr: ESwitch(macro name, reads, macro return super.readField(name)), pos: pos}, pos));
    fields.push(method("writeField", [{name: "name", type: macro : String}, {name: "value", type: macro : Dynamic}], macro : Bool,
      {expr: ESwitch(macro name, writes, macro return super.writeField(name, value)), pos: pos}, pos));
    return fields;
  }

  static function addIdentity(fields : Array<Field>) {
    var meta = Context.getLocalClass().get().meta;
    var ids = strings(meta.extract(":component"));
    if (ids.length == 0) return;
    var pos = Context.currentPos();
    var former = strings(meta.extract(":formerly"));
    fields.push(method("componentId", [], macro : String, macro return $v{ids[0]}, pos));
    fields.push(method("formerIds", [], macro : Array<String>, macro return $v{former}, pos));
  }

  static function strings(entries : Metadata) : Array<String> {
    var values = [];
    for (entry in entries) for (param in entry.params) values.push(ExprTools.getValue(param));
    return values;
  }

  static function describe(field : Field, meta : MetadataEntry) : Editable {
    var params : Array<Dynamic> = meta.params == null ? [] : [for (param in meta.params) ExprTools.getValue(param)];
    return {
      name: field.name,
      label: params.length > 0 ? params[0] : field.name,
      kind: kindOf(field),
      min: params.length > 1 ? params[1] : null,
      max: params.length > 2 ? params[2] : null,
      hint: hintOf(field),
      former: strings(field.meta.filter(entry -> entry.name == ":formerly")),
    };
  }

  static function hintOf(field : Field) : Expr {
    var choice = Lambda.find(field.meta, entry -> entry.name == ":choice");
    if (choice != null) {
      var options = strings([choice]);
      checkChoiceDefault(field, options);
      return macro scene.FieldInfo.FieldHint.HChoice($v{options});
    }
    var ref = Lambda.find(field.meta, entry -> entry.name == ":ref");
    if (ref != null) {
      var tables = strings([ref]);
      if (tables.length != 1) Context.error('@:ref alan ${field.name}: tek bir tablo adı verilmeli', field.pos);
      return macro scene.FieldInfo.FieldHint.HRef($v{tables[0]});
    }
    var name = "HNone";
    for (hint in [":asset" => "HAsset", ":entity" => "HEntity", ":prefab" => "HPrefab", ":color" => "HColor", ":dialog" => "HDialog"].keyValueIterator())
      if (Lambda.exists(field.meta, entry -> entry.name == hint.key)) name = hint.value;
    return macro $p{["scene", "FieldInfo", "FieldHint", name]};
  }

  // Seçenek silinip varsayılan değer unutulursa yeni nesneler geçersiz değerle oluşurdu.
  static function checkChoiceDefault(field : Field, options : Array<String>) {
    var value = switch (field.kind) {
      case FVar(_, {expr: EConst(CString(text))}): text;
      default: Context.error('@:choice alan ${field.name}: tip String olmalı ve varsayılan değeri sabit metin olmalı', field.pos);
    };
    if (options.indexOf(value) < 0)
      Context.error('@:choice alan ${field.name}: varsayılan "$value" seçeneklerde yok (${options.join(", ")})', field.pos);
  }

  static function kindOf(field : Field) : String {
    var type = switch (field.kind) {
      case FVar(t, _), FProp(_, _, t, _): t;
      default: null;
    };
    switch (type) {
      case TPath({name: "Float", params: []}): return "KFloat";
      case TPath({name: "Int", params: []}): return "KInt";
      case TPath({name: "Bool", params: []}): return "KBool";
      case TPath({name: "String", params: []}): return "KString";
      case TPath({name: "Array", params: [TPType(TPath({name: "String", params: []}))]}): return "KStringList";
      case TPath({name: "Array", params: [TPType(TPath({name: "Float", params: []}))]}): return "KFloatList";
      default:
        return Context.error('@:editable alan ${field.name}: tip açıkça Float, Int, Bool, String, Array<String> veya Array<Float> olmalı', field.pos);
    }
  }

  static function method(name : String, args : Array<FunctionArg>, ret : ComplexType, body : Expr, pos : Position) : Field {
    return {
      name: name,
      access: [APublic, AOverride],
      kind: FFun({args: args, ret: ret, expr: body}),
      pos: pos,
    };
  }
}
#end
