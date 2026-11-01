package components;

import scene.AssetWatch;
import scene.Component;
import scene.ModelLibrary;

// Asset Browser'dan sahneye sürüklenen modeller bu bileşenle eklenir.
@:component("model")
class ModelComponent extends Component {
  @:editable("Model") @:asset public var path : String = "";

  var model : Null<h3d.scene.Object>;
  var watched : Null<String>;
  var onChanged : Null<Void->Void>;

  override function onCreate() {
    // Editörde yazılan yanlış yol sahneyi düşürmesin.
    if (path == "" || !hxd.Res.loader.exists(path)) return;
    var file = watched = path;
    onChanged = () -> {
      ModelLibrary.forget(file);
      refresh();
    };
    AssetWatch.add(file, onChanged);
    model = ModelLibrary.load(file);
    entity.object.addChild(model);
  }

  override function onDestroy() {
    if (model != null) model.remove();
    if (watched != null) AssetWatch.remove(watched, onChanged);
    model = null;
    watched = null;
  }
}
