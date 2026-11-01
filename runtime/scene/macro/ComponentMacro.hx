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
  var hint : String;
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
      hint: $p{["scene", "FieldInfo", "FieldHint", item.hint]},
    })];
    var reads = [for (item in editable) {
      var name = item.name;
      {values: [macro $v{name}], expr: macro return this.$name};
    }];
    var writes = [for (item in editable) {
      var name = item.name;
      var names = [name].concat(item.former);
      {values: [for (entry in names) macro $v{entry}], expr: macro { this.$name = value; return true; }};
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

  static function hintOf(field : Field) : String {
    if (Lambda.exists(field.meta, entry -> entry.name == ":asset")) return "HAsset";
    if (Lambda.exists(field.meta, entry -> entry.name == ":entity")) return "HEntity";
    return "HNone";
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
      default:
        return Context.error('@:editable alan ${field.name}: tip açıkça Float, Int, Bool veya String olmalı', field.pos);
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
