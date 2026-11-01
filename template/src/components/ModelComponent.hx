package components;

import scene.AssetWatch;
import scene.Component;

// Asset Browser'dan sahneye sürüklenen modeller bu bileşenle eklenir.
@:component("model")
class ModelComponent extends Component {
  @:editable("Model") @:asset public var path : String = "";

  var model : Null<h3d.scene.Object>;
  var watched : Null<String>;

  override function onCreate() {
    // Editörde yazılan yanlış yol sahneyi düşürmesin.
    if (path == "" || !hxd.Res.loader.exists(path)) return;
    watched = path;
    AssetWatch.add(watched, refresh);
    model = new h3d.prim.ModelCache().loadModel(hxd.Res.load(path).toModel());
    entity.object.addChild(model);
  }

  override function onDestroy() {
    if (model != null) model.remove();
    if (watched != null) AssetWatch.remove(watched, refresh);
    model = null;
    watched = null;
  }
}
