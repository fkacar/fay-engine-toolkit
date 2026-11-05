package scene.editor.agent;

import haxe.io.Path;
import sys.FileSystem;
import scene.Component;
import scene.Entity;
import scene.FieldInfo;
import scene.GroundHeight;
import scene.Guid;
import scene.Marker;
import scene.PathMarker;
import scene.data.DataTable;
import scene.data.SceneData.ComponentData;
import scene.data.SceneData.EntityData;
import scene.editor.agent.AgentServer.AgentReply;
import scene.editor.commands.AddComponentCommand;
import scene.editor.commands.AddEntitiesCommand;
import scene.editor.commands.GroupCommand;
import scene.editor.commands.RemoveComponentCommand;
import scene.editor.commands.RemoveEntitiesCommand;
import scene.editor.commands.SetActiveCommand;
import scene.editor.commands.SetDialogCommand;
import scene.editor.commands.SetFieldCommand;
import scene.editor.commands.SetNameCommand;
import scene.editor.commands.SetTableCommand;
import scene.editor.commands.SetTransformCommand;
import scene.nav.NavWorld;
import scene.story.Dialog;
import scene.story.DialogLayout;

// Faz C: ajan editörde değişiklik yapar. Her çağrı editör komutlarıyla uygulanır ve tasarımcının
// geçmişine tek "Ajan: ..." adımı olarak girer. Çağrının bir işlemi hatalıysa öncekiler geri alınır,
// hiçbir şey değişmez. Alanlar Inspector'la aynı kurallarla denetlenir.
class EditTools {
  static inline var SEARCH_STEP = 1.;
  static inline var SEARCH_RADIUS = 30.;
  static inline var RESOURCE_DIRECTORY = "res";
  static inline var IMPORT_WAIT_FRAMES = 3;
  static inline var IMPORT_TIMEOUT = 30.;

  static var MODEL_TYPES = ["fbx", "hmd"];

  var editor : Editor;

  public function new(editor : Editor, server : AgentServer) {
    this.editor = editor;
    function tool(name : String, description : String, properties : Dynamic, run : Dynamic->Dynamic, readOnly : Bool, ?required : Array<String>) {
      var schema : Dynamic = {type: "object", properties: properties};
      if (required != null) schema.required = required;
      server.add({name: name, description: description, schema: schema, readOnly: readOnly, run: args -> ({value: run(args)} : AgentReply)});
    }
    var revision = {type: "integer", description: "Okuduğun durumun revizyonu (get_overview history.revision). Arada değişiklik olduysa çağrı reddedilir"};
    tool("edit_scene", "Sahneyi değiştirir. operations sırayla uygulanır, hepsi tek geri alma adımıdır. İşlemler:\n"
      + "create {key?, name, type? (bileşen veya işaretçi kimliği, örn. spawn, patrol_route, trigger), prefab? (yol), position [x,y] veya [x,y,z], rotationDegrees?, parent? (kimlik veya $key), fields? (type bileşeninin alanları), components? [{type, fields}], waypoints? [[x,y],...] (rota işaretçisi için)}\n"
      + "set {id, name?, position?, rotationDegrees?, scale?, visibleInGame?, components? [{type, fields}]}\n"
      + "delete yayındaki (oyunculara ulaşmış, durumlu) nesneyi silmez; bilerek silmek için allowReleased: true. Yerine yenisi yapılırsa kayit_esleri tablosuna eşle\n"
      + "add_component {id, type, fields?} · remove_component {id, type} · delete {ids}\n"
      + "Alan adı kimlik veya Inspector etiketi olabilir. Bir alan aynı çağrıda oluşturulan nesneyi \"$key\" ile gösterebilir. x,y verilince nesne sürükleyip bırakmadaki gibi zemine oturur: en alt noktası zemine değer (işaretçide z zeminden yüksekliktir). [x,y,z] verilirse z olduğu gibi yazılır.", {
      label: {type: "string", description: "Geçmişte görünecek ad, örn. kasabaya devriye"},
      operations: {type: "array", items: {type: "object"}},
      expectedRevision: revision,
    }, editScene, false, ["label", "operations"]);
    tool("edit_table", "Bir veri tablosunu değiştirir: set [{id, values}], add [{id, values}], delete [ids]. Kullanılan satır silinmez, kimliği değişmez. "
      + "addColumns [{name, title, type, options?, table?}]: type metin, sayi, tam, evet_hayir, secim (options gerekir), baglanti (table gerekir), renk, varlik (res altındaki dosya yolu, ör. models/tufek/tufek.hmd); var olan satırlar varsayılan değeri alır. removeColumns [ad]. Sütunlar satırlardan önce işlenir.", {
      table: {type: "string"}, set: {type: "array", items: {type: "object"}}, add: {type: "array", items: {type: "object"}},
      addColumns: {type: "array", items: {type: "object"}}, removeColumns: {type: "array", items: {type: "string"}},
      delete: {type: "array", items: {type: "string"}}, label: {type: "string"}, expectedRevision: revision,
    }, editTable, false, ["table"]);
    tool("edit_dialog", "Bir diyaloğu değiştirir veya oluşturur (create true). nodes: düğümleri kimliğe göre ekler veya günceller (diyalog dosyasındaki biçim: id, type baslangic|satir|secenek|kosul|olay|bitis, speaker, text, next, choices [{text, next}], kind degisken|esya, name, value, yes, no, event). remove: silinecek düğümler. arrange: düğümleri akışa göre dizer.", {
      id: {type: "string"}, title: {type: "string"}, create: {type: "boolean"}, nodes: {type: "array", items: {type: "object"}},
      remove: {type: "array", items: {type: "integer"}}, arrange: {type: "boolean"}, label: {type: "string"}, expectedRevision: revision,
    }, editDialog, false, ["id"]);
    tool("set_camera", "Tasarımcının kamerasını yerleştirir. target [x,y] veya [x,y,z] ya da entity (kimlik); distance metre; yawDegrees, pitchDegrees (negatif aşağı bakar); topDown true zemine dik bakar. Verilmeyenler aynı kalır.", {
      target: {type: "array", items: {type: "number"}}, entity: {type: "string"}, distance: {type: "number"},
      yawDegrees: {type: "number"}, pitchDegrees: {type: "number"}, topDown: {type: "boolean"},
    }, setCamera, false);
    tool("set_selection", "Tasarımcının seçimini değiştirir; focus true ise kamera seçime odaklanır. Boş liste seçimi kaldırır.", {
      ids: {type: "array", items: {type: "string"}}, focus: {type: "boolean"},
    }, setSelection, false, ["ids"]);
    tool("save", "Sahneyi, tabloları ve diyalogları kaydeder. Yalnızca tasarımcı isteyince kullan.", {}, _ -> save(), false);
    tool("load_cells", "Dünyanın hücrelerini yükler (tasarımcının Dünya sekmesindeki haritada hücreye tıklaması gibi): cells [hücre kimlikleri] "
      + "ya da around [x,y] ve radius (metre, varsayılan 0: yalnızca o noktanın hücresi). Yüklü olmayan hücredeki nesne sahnede yoktur; "
      + "find_entities, edit_scene ve set_camera ondan önce. Geri alma adımı yazmaz. Sonuç: yüklenen ve zaten yüklü hücreler.",
      {cells: {type: "array", items: {type: "integer"}}, around: {type: "array", items: {type: "number"}}, radius: {type: "number"}}, loadCells, false);
    tool("undo", "Geri alır (Cmd+Z). steps kadar adım.", {steps: {type: "integer"}}, args -> step(args.steps, true), false);
    tool("redo", "İleri alır. steps kadar adım.", {steps: {type: "integer"}}, args -> step(args.steps, false), false);
    tool("find_walkable_point", "x, y'ye en yakın yürünebilir nokta (yol ızgarasına göre), radius metre içinde.", {
      x: {type: "number"}, y: {type: "number"}, radius: {type: "number"},
    }, args -> walkablePoint(args.x, args.y, args.radius == null ? SEARCH_RADIUS : args.radius), true, ["x", "y"]);
    tool("find_path", "İki nokta arasında yürünebilir yol: noktalar, uzunluk ve hedefe varılıp varılmadığı.", {
      from: {type: "array", items: {type: "number"}}, to: {type: "array", items: {type: "number"}},
    }, args -> path(args.from, args.to), true, ["from", "to"]);
    tool("record_release_ids", "Oyun dağıtılırken (Steam'e yükleme): dünyadaki durumlu nesnelerin (tetikleyici, doğma alanı, ekip üyesi) kimliklerini res/kayit/kimlikler.json'a yazar. "
      + "Bundan sonra bu nesneler silinirse Uyarılar'a düşer, silerken onay sorulur. Liste yalnızca büyür: önceki yayından olup dünyadan kalkmış nesneler listede kalır, "
      + "unresolved onlardan eşlenmemiş ve bırakılmamış olanlardır (tasarımcıya söyle, map_saved_entity ile çöz). Dosya işidir, geri alma adımı değildir. Tasarımcı istemedikçe çağırma.", {}, _ -> {
        var recorded = editor.releaseIds.record();
        editor.document.validate();
        ({path: ReleaseIds.PATH, count: recorded.count, unresolved: [for (item in recorded.unresolved) {id: item.id, name: item.name, types: item.types}]} : Dynamic);
      }, false);
    tool("map_saved_entity", "Yayındaki silinmiş bir nesnenin oyuncu kayıtlarındaki durumunu yerine geçen nesneye bağlar (kayit_esleri tablosu, tek geri alma adımı). "
      + "from eski kimlik (get_warnings'teki 'Yayındaki ... dünyada yok' uyarısından), to yeni nesnenin kimliği. "
      + "Tasarımcı nesneyi bilerek kaldırdıysa ve yerine bir şey gelmeyecekse to yerine abandon: true (Bırak): uyarı kapanır, oyuncunun o nesnedeki durumu bağsız kalır. Bırakmaya tasarımcı karar verir.", {
        from: {type: "string"}, to: {type: "string"}, abandon: {type: "boolean"},
      }, (args : Dynamic) -> {
        var old = Lambda.find(editor.releaseIds.list(), item -> item.id == args.from);
        if (old == null) throw 'yayın listesinde yok: ${args.from}';
        if ((args.abandon == true) == (args.to != null)) throw "ya to ya da abandon: true ver";
        if (args.abandon == true) {
          editor.releaseIds.abandon(args.from, old.name);
          return ({abandoned: args.from, revision: editor.commands.revision} : Dynamic);
        }
        if (editor.scene.find(args.to) == null) throw 'yeni nesne yok veya hücresi yüklü değil: ${args.to}';
        editor.releaseIds.map(args.from, args.to, old.name);
        ({mapped: args.from, to: args.to, revision: editor.commands.revision} : Dynamic);
      }, false, ["from"]);
    tool("list_models", "Modeller. models: res altındaki yerleştirilebilir modeller. catalog: dosya → model kataloğundaki kimlik (oyun kataloğu kullanıyorsa); model alanlarına dosya değil bu kimlik yazılır, kataloğu olmayan dosya için import_model satırı ekler. notImported: assets altında olup içe aktarılmamış veya kaynağı ya da ayarı (klasör ayarı dahil) sonradan değişmiş modeller (FBX, GLB, glTF, OBJ), import_model ile alınır.", {}, _ -> listModels(), true);
    server.add({name: "import_model", readOnly: false, run: importModel,
      description: "assets altındaki bir modeli (FBX; GLB, glTF ve OBJ Blender'la çevrilir) Asset Browser'daki Model içe aktar gibi dönüştürür, res/models altına yazar (assets/models/mock altındakiler res/models/mock altına). Dosya işidir, geri alma adımı değildir; yeniden alınca sahnelerdeki yol değişmez. Büyük modelde editör bir süre tepki vermez. Oyun model kataloğu kullanıyorsa model katalogda yoksa satırı eklenir (tek Ajan: adımı) ve catalog kimliği döner: model alanlarına bu kimliği yaz, path'i değil. Modeli her yerde değiştirmek için katalog satırının dosyasını değiştir (edit_table). "
        + "Ayarlar kaynağın yanındaki <ad>.aktarim.json'a yazılır; folder verilirse klasör ayarına (klasor.aktarim.json): o klasör ve alt klasörlerdeki bütün modeller onu kullanır, modelin kendi dosyasındaki aynı adlı klip ve nokta onu ezer. Aynı iskeletli bir paketin klipleri ve eklem eşlemesi böyle bir kez yazılır; klasördeki öbür modeller list_models'te notImported görünür, onları da al. "
        + "trim verilirse kaynağın yanındaki .aktarim.json'a yazılır ve kutuların içinde kalan üçgenler atılır (yapay zekâ modellerindeki yer plakası, havada kalan parça); [] kırpmayı kaldırır. Kutuları model_info'nun sınırlarına ve taban haritasına göre seç. "
        + "sockets takma noktalarıdır, aynı dosyaya yazılır; [] verilirse iskeletli modelde varsayılanlar (sag_el, sol_el, sirt, bel, bas) kullanılır. Sonucu preview_character ile gözle denetle.",
      schema: {type: "object", properties: {
        source: {type: "string", description: "assets yolu veya dosya adının bir parçası"},
        trim: {type: "array", description: "[{min: [x, y, z], max: [x, y, z], note?}], modelin kendi birimleriyle, Z yukarı", items: {type: "object"}},
        clips: {type: "array", description: "[{name, source, take?, arms?}]: aynı iskeletle üretilmiş başka FBX'lerin klipleri bu modele eklenir. take: dosyada birden çok klip varsa hangisi (model_info takes listesindeki ad, Walk_Loop; \"Armature|Walk_Loop\" gibi adlar sonundan eşleşir). source boşsa klip modelin kendi dosyasından alınır, take zorunlu. Karakter durma, yurume, kosma, hizli_kosma adlarını kullanır; silah türünün seti _tur ekiyle (durma_tufek). arms verilirse kollar (köprücükten ele) o FBX'in klibinin ilk karesinde sabit kalır, gövde ve bacaklar source'tan: kütüphanede olmayan silahlı klip böyle türetilir (silahsız durma + tüfekli koşunun kolları). [] klipleri kaldırır", items: {type: "object"}},
        sockets: {type: "array", description: "[{name, joint, offset: [x, y, z], rotation: [x, y, z]}]: takma noktaları. Karakterde eksenler X ileri, Y sağ, Z yukarı (bağlama pozundaki gövdeye göre); offset metre, eklemin dinlenme pozundaki yerine göre; rotation derece. El noktasında X bilekten parmaklara, Z yumruğun deliği boyunca başparmağa. Silah modelinde joint boş, name tutamak: kabzanın avuçta duracağı yer; tüfekte X namlu yönünde, Z yukarı; sapı olan silahta (balta, kılıç) Z saptan başa, X başın ya da ağzın yönü", items: {type: "object"}},
        joints: {type: "object", description: "Eklem eşlemesi {standart ad: iskeletteki ad}, ör. {\"Hips\": \"pelvis\"}. Mixamo ve Rigify (DEF-hips, DEF-hand.R) adları kendiliğinden tanınır; yalnızca tanınmayan ya da yanlış eşlenen eklemi ver. Standart adlar: Hips, Spine, Spine1, Spine2, Neck, Head, Left/Right + Shoulder, Arm, ForeArm, Hand, UpLeg, Leg, Foot, ToeBase. {} kaldırır. Çözülen eşleme model_info standardJoints"},
        length: {type: "number", description: "İskeletsiz modelin (silah, eşya) en uzun kenarı, metre; model bu boya ölçeklenir (silah paketleri 1 birime sığdırılmış gelir). 0 kaldırır"},
        grip: {type: ["boolean", "string"], description: "true: iskeletsiz modele tutamak noktası şekilden tahmin edilir (ince uç sap; elle verilen tutamak önce gelir). \"klasorden\" kaldırır"},
        blender: {type: ["boolean", "string"], description: "true: FBX önce Blender'la yeniden yazılır (başka aracın ölçeğiyle gelen dosya, kemikler 100 kat büyükse). GLB/glTF/OBJ her zaman çevrilir. \"klasorden\" kaldırır"},
        skins: {type: "string", description: "Kaplamalar: kaynağın klasörüne göre kalıp, örn. \"textures/{ad}_skin*.png\" ({ad} model dosyasının adı, tek *). Uyan dokular modelin yanına kopyalanır, adları model.json'un skins alanına yazılır; oyun çeşitlemede her karaktere birini seçer. \"\" kaldırır"},
        folder: {type: ["boolean", "string"], description: "Ayarları modelin dosyası yerine klasör ayarına yaz: true kaynağa en yakın klasor.aktarim.json (yoksa kaynağın klasörü), metin ise assets altında kaynağın üst klasörlerinden biri. trim klasöre yazılmaz"},
      }, required: ["source"]}});
    server.add({name: "model_info", readOnly: true, run: modelInfo,
      description: "assets altındaki bir modeli dönüştürmeden inceler (GLB Blender'la çevrilir): sınırlar (modelin birimleriyle, Z yukarı, length uygulanmadan), üçgen sayısı, iskelet eklemleri, standardJoints (çözülen eklem eşlemesi), takes (dosyadaki klip adları, clips'in take alanı için), klipler, takma noktaları (sockets: ayardakiler, character.sockets: oyunun kullanacakları, varsayılanlar dahil), etkin ayar (klasör ayarlarıyla birleşik; inherited: klasör dosyaları; length, grip, blender, jointOverrides), kırpma ayarı ve taban haritası. Taban haritası alt %3'teki üçgenlerin yukarıdan sayısıdır: ayaklar iki küme olur, başka küme genellikle fazlalıktır. Büyük modelde editör bir süre tepki vermez.",
      schema: {type: "object", properties: {
        source: {type: "string", description: "assets yolu veya dosya adının bir parçası"},
        floorFraction: {type: "number", description: "Taban haritasının yüksekliği, modelin boyuna oranla (varsayılan 0.03)"},
      }, required: ["source"]}});
  }

  function editScene(args : Dynamic) : Dynamic {
    checkRevision(args.expectedRevision);
    var operations : Array<Dynamic> = args.operations;
    if (operations == null || operations.length == 0) throw "operations boş";
    var label = 'Ajan: ${args.label == null ? "sahne düzenlemesi" : args.label}';
    var applied : Array<Command> = [];
    var keys = new Map<String, String>();
    var created : Array<String> = [], changed : Array<String> = [];
    function run(command : Command) {
      command.execute();
      applied.push(command);
    }
    try {
      for (i in 0...operations.length) {
        var operation = operations[i];
        try apply(operation, keys, run, label, created, changed) catch (e : Dynamic) throw '${i + 1}. işlem (${operation.op}): $e';
      }
    } catch (e : Dynamic) {
      var k = applied.length;
      while (k-- > 0) applied[k].undo();
      throw '$e. Hiçbir şey değişmedi.';
    }
    editor.commands.record(new GroupCommand(label, applied));
    editor.document.validate();
    var ids = created.concat(changed);
    var result : Dynamic = {
      label: label,
      revision: editor.commands.revision,
      created: [for (key => id in keys) {key: key, id: id}],
      entities: [for (id in ids) if (editor.scene.find(id) != null) brief(editor.scene.find(id))],
      warnings: [for (issue in editor.document.issues) if (issue.entity != null && ids.indexOf(issue.entity.id) >= 0) issue.message],
    };
    return result;
  }

  function apply(operation : Dynamic, keys : Map<String, String>, run : Command->Void, label : String, created : Array<String>, changed : Array<String>) {
    var registry = editor.scene.registry;
    switch (operation.op) {
      case "create":
        var id = Guid.make();
        if (operation.key != null) keys.set(operation.key, id);
        var items = [];
        var item = new EntityData(id, operation.name != null ? operation.name : operation.type != null ? titleOf(operation.type) : "Nesne");
        var isMarker = operation.type != null && Std.isOfType(registry.create(operation.type), Marker);
        item.position = place(operation.position, isMarker);
        if (operation.rotationDegrees != null) item.rotation = rotation(operation.rotationDegrees);
        if (operation.parent != null) {
          var parent = resolve(operation.parent, keys);
          if (editor.scene.find(parent) == null && keys.get(operation.parent.substr(1)) == null) throw 'üst nesne yok: ${operation.parent}';
          item.parent = parent;
        }
        if (operation.prefab != null) {
          if (editor.actions.prefabFiles().indexOf(operation.prefab) < 0) throw 'prefab yok: ${operation.prefab}';
          item.prefab = operation.prefab;
        }
        if (operation.type != null) item.components.push(componentData(operation.type, operation.fields, keys));
        var extra : Array<Dynamic> = operation.components == null ? [] : operation.components;
        for (spec in extra) item.components.push(componentData(spec.type, spec.fields, keys));
        items.push(item);
        if (operation.waypoints != null) {
          if (!Std.isOfType(registry.create(operation.type), PathMarker)) throw 'waypoints yalnızca rota işaretçisinde: ${operation.type}';
          var points : Array<Array<Float>> = operation.waypoints;
          for (point in points) items.push(editor.actions.waypointData(id, point[0] - item.position[0], point[1] - item.position[1]));
        }
        run(new AddEntitiesCommand(editor.scene, items, label));
        if (!isMarker && item.parent == null && (operation.position : Array<Dynamic>).length < 3) {
          var entity = editor.scene.find(id);
          var before = SetTransformCommand.capture(entity);
          if (editor.actions.sitOnGround(entity) && !SetTransformCommand.same(before, SetTransformCommand.capture(entity)))
            run(new SetTransformCommand(entity, before, SetTransformCommand.capture(entity)));
        }
        created.push(id);
      case "set":
        var entity = existing(operation.id, created);
        if (operation.name != null) run(new SetNameCommand(entity, entity.name, operation.name));
        if (operation.position != null || operation.rotationDegrees != null || operation.scale != null) {
          var before = SetTransformCommand.capture(entity);
          var settle = false;
          if (operation.position != null) {
            var isMarker = Lambda.exists(entity.components, c -> Std.isOfType(c, Marker));
            var at = place(operation.position, isMarker);
            entity.setPosition(at[0], at[1], at[2]);
            settle = !isMarker && entity.parent == null && (operation.position : Array<Dynamic>).length < 3;
          }
          if (operation.rotationDegrees != null) {
            var turn = rotation(operation.rotationDegrees);
            entity.setRotation(turn[0], turn[1], turn[2]);
          }
          if (operation.scale != null) {
            var size = Std.isOfType(operation.scale, Array) ? (operation.scale : Array<Float>) : [operation.scale, operation.scale, operation.scale];
            entity.setScale(size[0], size[1], size[2]);
          }
          if (settle) editor.actions.sitOnGround(entity);
          run(new SetTransformCommand(entity, before, SetTransformCommand.capture(entity)));
        }
        if (operation.visibleInGame != null) run(new SetActiveCommand(entity, operation.visibleInGame == true));
        var specs : Array<Dynamic> = operation.components == null ? [] : operation.components;
        for (spec in specs) {
          var component = componentOf(entity, spec.type);
          for (name in Reflect.fields(spec.fields)) {
            var field = fieldOf(component, name);
            var value = convert(field, Reflect.field(spec.fields, name), keys);
            run(new SetFieldCommand(component, field.name, component.readField(field.name), value, label));
          }
        }
        changed.push(entity.id);
      case "add_component":
        var entity = existing(operation.id, created);
        if (entity.instanceRoot != null) throw 'prefab kopyasına bileşen eklenmez, prefab\'ı aç: ${entity.name}';
        var component = registry.create(operation.type);
        if (component == null) throw 'bilinmeyen bileşen: ${operation.type}';
        var fields : Dynamic = operation.fields == null ? {} : operation.fields;
        for (name in Reflect.fields(fields)) {
          var field = fieldOf(component, name);
          component.writeField(field.name, convert(field, Reflect.field(fields, name), keys));
        }
        run(new AddComponentCommand(entity, component));
        changed.push(entity.id);
      case "remove_component":
        var entity = existing(operation.id, created);
        if (entity.instanceRoot != null) throw 'prefab kopyasından bileşen kaldırılmaz, prefab\'ı aç: ${entity.name}';
        run(new RemoveComponentCommand(entity, componentOf(entity, operation.type)));
        changed.push(entity.id);
      case "delete":
        var ids : Array<String> = operation.ids;
        var entities = [for (id in ids) existing(id, created)];
        for (entity in entities) if (entity.isPrefabPart) throw 'prefab parçası silinmez, prefab\'ı aç: ${entity.name}';
        // Yayındaki nesne: oyuncu kayıtlarında durumu var. Bilerek silinir; yerine yenisi yapılırsa eşlenir.
        var released = editor.releaseIds.protectedNames(entities);
        if (released.length > 0 && operation.allowReleased != true)
          throw 'yayındaki nesne: ${released.join(", ")}. Oyuncu kayıtlarında durumu var (çalışmış tetikleyici, NPC\'ler); silinirse oyuncularda yeniden başlar. '
            + 'Yerine yenisini yapacaksan sildikten sonra get_warnings\'teki öneriyle kayit_esleri tablosuna eşle (edit_table, satır kimliği eski kimlik, yeni sütunu yeni kimlik). Bilerek silmek için allowReleased: true';
        run(new RemoveEntitiesCommand(editor.scene, entities));
      default:
        throw 'bilinmeyen işlem: ${operation.op}. create, set, add_component, remove_component, delete';
    }
  }

  function componentData(type : String, fields : Dynamic, keys : Map<String, String>) : ComponentData {
    var sample = editor.scene.registry.create(type);
    if (sample == null) throw 'bilinmeyen bileşen: $type. Türler get_schema\'da';
    var data = new ComponentData(type);
    if (fields != null)
      for (name in Reflect.fields(fields)) {
        var field = fieldOf(sample, name);
        data.fields.set(field.name, convert(field, Reflect.field(fields, name), keys));
      }
    return data;
  }

  // Inspector'daki kurallar: tür, sınırlar, seçenekler, tablo satırı, diyalog ve nesne bağlantısı.
  function convert(field : FieldInfo, raw : Dynamic, keys : Map<String, String>) : Dynamic {
    var label = '${field.label} (${field.name})';
    switch (field.kind) {
      case KFloat:
        if (!Std.isOfType(raw, Float)) throw '$label sayı olmalı';
        var value : Float = raw;
        if (field.min != null && value < field.min || field.max != null && value > field.max) throw '$label ${field.min} ile ${field.max} arasında olmalı';
        return value;
      case KInt:
        if (field.hint != null && field.hint.match(HColor) && Std.isOfType(raw, String)) {
          var hex = StringTools.replace(raw, "#", "");
          var parsed = Std.parseInt("0x" + hex);
          if (parsed == null || hex.length != 6) throw '$label #RRGGBB biçiminde renk olmalı';
          return parsed;
        }
        if (!Std.isOfType(raw, Int)) throw '$label tam sayı olmalı';
        var value : Int = raw;
        if (field.min != null && value < field.min || field.max != null && value > field.max) throw '$label ${field.min} ile ${field.max} arasında olmalı';
        return value;
      case KBool:
        if (!Std.isOfType(raw, Bool)) throw '$label true veya false olmalı';
        return raw;
      case KString:
        if (!Std.isOfType(raw, String)) throw '$label metin olmalı';
        var value : String = raw;
        if (StringTools.startsWith(value, "$") && keys.exists(value.substr(1))) value = keys.get(value.substr(1));
        if (value == "" || field.hint == null) return value;
        switch (field.hint) {
          case HChoice(options): if (options.indexOf(value) < 0) throw '$label şunlardan biri olmalı: ${options.join(", ")}';
          case HRef(table): if (!editor.data.exists(table, value)) throw '$label: $table tablosunda "$value" yok. Satırlar: ${editor.data.tables.exists(table) ? editor.data.tables.get(table).ids().join(", ") : "tablo yok"}';
          case HDialog: if (!editor.dialogs.exists(value)) throw '$label: "$value" diyaloğu yok. Diyaloglar: ${editor.dialogs.ids().join(", ")}';
          case HEntity: if (editor.scene.find(value) == null && !Lambda.exists(keys, id -> id == value)) throw '$label: "$value" kimlikli nesne yok';
          case HPrefab: if (editor.actions.prefabFiles().indexOf(value) < 0) throw '$label: prefab yok: $value';
          default:
        }
        return value;
      case KStringList:
        if (!Std.isOfType(raw, Array)) throw '$label metin listesi olmalı';
        return [for (item in (raw : Array<Dynamic>)) Std.string(item)];
      case KFloatList:
        if (!Std.isOfType(raw, Array)) throw '$label sayı listesi olmalı';
        return [for (item in (raw : Array<Dynamic>)) (item : Float)];
    }
  }

  function fieldOf(component : Component, name : String) : FieldInfo {
    var wanted = name.toLowerCase();
    for (field in component.describeFields()) if (field.name == name || field.label.toLowerCase() == wanted) return field;
    throw '${component.title()} bileşeninde "$name" alanı yok. Alanlar: ${[for (field in component.describeFields()) '${field.name} (${field.label})'].join(", ")}';
  }

  function componentOf(entity : Entity, type : String) : Component {
    var wanted = type.toLowerCase();
    for (component in entity.components) if (component.componentId() == type || component.title().toLowerCase() == wanted) return component;
    throw '${entity.name} nesnesinde $type bileşeni yok. Bileşenler: ${[for (c in entity.components) c.componentId()].join(", ")}';
  }

  function existing(id : String, created : Array<String>) : Entity {
    if (created.indexOf(id) >= 0) throw 'aynı çağrıda oluşturulan nesne sonra değiştirilmez: alanlarını create içinde ver';
    var entity = editor.scene.find(id);
    if (entity == null) throw 'nesne yok veya hücresi yüklü değil: $id';
    return entity;
  }

  function resolve(value : String, keys : Map<String, String>) : String {
    return StringTools.startsWith(value, "$") && keys.exists(value.substr(1)) ? keys.get(value.substr(1)) : value;
  }

  // x, y verilince z zemine oturur; zemini bilen işaretçide z zeminden yüksekliktir.
  function place(position : Dynamic, isMarker : Bool) : Array<Float> {
    if (!Std.isOfType(position, Array) || (position : Array<Dynamic>).length < 2) throw "position [x, y] veya [x, y, z] olmalı";
    var at : Array<Float> = position;
    if (at.length >= 3) return [at[0], at[1], at[2]];
    var ground = editor.scene.service(GroundHeight);
    if (isMarker && ground != null) return [at[0], at[1], 0];
    return [at[0], at[1], ground == null ? 0 : ground.heightAt(at[0], at[1])];
  }

  static function rotation(value : Dynamic) : Array<Float> {
    if (Std.isOfType(value, Array)) return value;
    return [0, 0, (value : Float)];
  }

  function editTable(args : Dynamic) : Dynamic {
    checkRevision(args.expectedRevision);
    var name : String = args.table;
    var before = editor.data.text(name);
    if (before == null) throw 'Tablo yok: $name. Tablolar: ${editor.data.names().join(", ")}';
    var table = DataTable.read(name, before);
    var dropped : Array<String> = args.removeColumns == null ? [] : args.removeColumns;
    for (column in dropped) {
      if (table.column(column) == null) throw '${table.title} tablosunda "$column" sütunu yok';
      table.columns = table.columns.filter(item -> item.name != column);
      for (row in table.rows) row.remove(column);
    }
    var columns : Array<Dynamic> = args.addColumns == null ? [] : args.addColumns;
    for (spec in columns) {
      var column = checkColumn(table, spec);
      table.columns.push(column);
      for (row in table.rows) row.set(column.name, DataTable.defaultValue(column));
    }
    var removed : Array<String> = args.delete == null ? [] : args.delete;
    for (id in removed) {
      var used = DataUsage.find(editor, name, id);
      if (used.length > 0) throw '"$id" silinemez, kullanılıyor: ${DataUsage.describe(used)}';
      if (table.find(id) == null) throw 'satır yok: $id';
      table.rows = table.rows.filter(row -> row.get("id") != id);
    }
    var added : Array<Dynamic> = args.add == null ? [] : args.add;
    for (spec in added) {
      if (table.find(spec.id) != null) throw 'bu kimlik zaten var: ${spec.id}';
      fill(table, table.addRow(spec.id), spec.values);
    }
    var updated : Array<Dynamic> = args.set == null ? [] : args.set;
    for (spec in updated) {
      var row = table.find(spec.id);
      if (row == null) throw 'satır yok: ${spec.id}';
      fill(table, row, spec.values);
    }
    var after = table.write();
    if (after != before) editor.commands.execute(new SetTableCommand('Ajan: ${args.label == null ? name + " tablosu" : args.label}', editor.data, name, before, after));
    editor.document.validate();
    return {table: name, rows: table.rows.length, revision: editor.commands.revision, changed: after != before};
  }

  // Data panelindeki "+ Sütun" gibi: ad başlıktan türer, seçim seçenek ister, bağlantı tablo ister.
  function checkColumn(table : DataTable, spec : Dynamic) : scene.data.DataTable.DataColumn {
    var title : String = spec.title != null ? spec.title : spec.name;
    var name = SceneDocument.cleanName(spec.name != null ? spec.name : title);
    var type : String = spec.type;
    if (name == "" || name == "id") throw 'sütun adı geçersiz: ${haxe.Json.stringify(spec)}';
    if (table.column(name) != null) throw 'bu adda sütun var: $name';
    if (DataTable.TYPES.indexOf(type) < 0) throw 'sütun türü şunlardan biri olmalı: ${DataTable.TYPES.join(", ")}';
    var column : scene.data.DataTable.DataColumn = {name: name, title: title, type: type};
    if (type == DataTable.CHOICE) {
      var options : Array<String> = spec.options;
      if (options == null || options.length == 0) throw '$name: seçim sütunu options ister';
      column.options = options;
    }
    if (type == DataTable.REFERENCE) {
      if (spec.table == null || editor.data.text(spec.table) == null) throw '$name: bağlantı sütunu var olan bir table ister';
      column.table = spec.table;
    }
    return column;
  }

  function fill(table : DataTable, row : haxe.DynamicAccess<Dynamic>, values : Dynamic) {
    if (values == null) return;
    for (key in Reflect.fields(values)) {
      var column = Lambda.find(table.columns, column -> column.name == key || column.title.toLowerCase() == key.toLowerCase());
      if (column == null) throw '${table.title} tablosunda "$key" sütunu yok. Sütunlar: ${[for (c in table.columns) c.name].join(", ")}';
      var value : Dynamic = Reflect.field(values, key);
      switch (column.type) {
        case DataTable.NUMBER: if (!Std.isOfType(value, Float)) throw '${column.title} sayı olmalı';
        case DataTable.INTEGER, DataTable.COLOR: if (!Std.isOfType(value, Int)) throw '${column.title} tam sayı olmalı';
        case DataTable.FLAG: if (!Std.isOfType(value, Bool)) throw '${column.title} true veya false olmalı';
        case DataTable.CHOICE: if (column.options == null || column.options.indexOf(value) < 0) throw '${column.title} şunlardan biri olmalı: ${column.options}';
        case DataTable.REFERENCE: if (value != "" && !editor.data.exists(column.table, value)) throw '${column.title}: ${column.table} tablosunda "$value" yok';
        case DataTable.ASSET: if (!Std.isOfType(value, String) || (value != "" && !FileSystem.exists('$RESOURCE_DIRECTORY/$value'))) throw '${column.title}: res altında dosya yok: $value';
        default: if (!Std.isOfType(value, String)) throw '${column.title} metin olmalı';
      }
      row.set(column.name, value);
    }
  }

  function editDialog(args : Dynamic) : Dynamic {
    checkRevision(args.expectedRevision);
    var id : String = args.id;
    var before = editor.dialogs.text(id);
    if (before == null && args.create != true) throw 'Diyalog yok: $id. Oluşturmak için create true. Diyaloglar: ${editor.dialogs.ids().join(", ")}';
    var dialog = before == null ? Dialog.create(id, args.title != null ? args.title : id) : Dialog.read(id, before);
    if (args.title != null) dialog.title = args.title;
    var nodes : Array<Dynamic> = args.nodes == null ? [] : args.nodes;
    for (spec in nodes) {
      if (spec.id == null || spec.type == null) throw "her düğümün id ve type alanı olmalı";
      if (!DialogWorkspace.TITLES.exists(spec.type)) throw 'bilinmeyen düğüm türü: ${spec.type}. Türler: ${[for (key in DialogWorkspace.TITLES.keys()) key].join(", ")}';
      var node = dialog.node(spec.id);
      if (node == null) {
        node = {id: spec.id, type: spec.type, x: 0, y: 0};
        dialog.nodes.push(node);
      }
      for (field in Reflect.fields(spec)) Reflect.setField(node, field, Reflect.field(spec, field));
    }
    var removed : Array<Int> = args.remove == null ? [] : args.remove;
    for (nodeId in removed) {
      var node = dialog.node(nodeId);
      if (node == null) throw 'düğüm yok: $nodeId';
      if (node.type == Dialog.START) throw "başlangıç düğümü silinmez";
      dialog.remove(nodeId);
    }
    for (node in dialog.nodes)
      for (target in DialogLayout.targets(node))
        if (target > 0 && dialog.node(target) == null) throw 'düğüm ${node.id}, olmayan düğüm $target\'e bağlı';
    if (args.arrange == true) for (nodeId => at in DialogLayout.arrange(dialog)) {
      dialog.node(nodeId).x = at.x;
      dialog.node(nodeId).y = at.y;
    }
    var after = dialog.write();
    Dialog.read(id, after);
    if (after != before) editor.commands.execute(new SetDialogCommand('Ajan: ${args.label == null ? dialog.title + " diyaloğu" : args.label}', editor.dialogs, id, before, after));
    editor.document.validate();
    return {id: id, nodes: dialog.nodes.length, revision: editor.commands.revision, changed: after != before,
      warnings: [for (issue in editor.document.issues) if (issue.dialog == id) issue.message]};
  }

  function setCamera(args : Dynamic) : Dynamic {
    var orbit = editor.viewport.camera;
    var target = orbit.lookPoint();
    if (args.entity != null) {
      var entity = editor.scene.find(args.entity);
      if (entity == null) throw 'nesne yok: ${args.entity}';
      var at = entity.object.getAbsPos();
      target = new Vec3(at.tx, at.ty, at.tz);
    } else if (args.target != null) {
      var at = place(args.target, false);
      target = new Vec3(at[0], at[1], at[2]);
    }
    var distance : Float = args.distance != null ? args.distance : orbit.distance;
    var yaw : Float = args.yawDegrees != null ? args.yawDegrees * Math.PI / 180 : orbit.yaw;
    var pitch : Float = args.topDown == true ? -Math.PI / 2 : args.pitchDegrees != null ? args.pitchDegrees * Math.PI / 180 : orbit.pitch;
    if (editor.dialogWorkspace.isOpen) editor.dialogWorkspace.close();
    orbit.place(target, distance, yaw, pitch);
    var look = orbit.lookPoint();
    return {target: [round(look.x), round(look.y), round(look.z)], distance: round(orbit.distance), yawDegrees: round(orbit.yaw * 180 / Math.PI), pitchDegrees: round(orbit.pitch * 180 / Math.PI)};
  }

  function setSelection(args : Dynamic) : Dynamic {
    var ids : Array<String> = args.ids;
    var entities = [for (id in ids) {
      var entity = editor.scene.find(id);
      if (entity == null) throw 'nesne yok: $id';
      entity;
    }];
    editor.selection.set(entities);
    if (args.focus == true && entities.length > 0) editor.actions.focus();
    return {selection: [for (entity in entities) brief(entity)]};
  }

  function save() : Dynamic {
    var saved = editor.document.save();
    return {
      saved: saved,
      conflicts: [for (conflict in editor.diskGuard.conflicts) {path: conflict.path, units: conflict.units}],
      unsavedFiles: editor.document.unsavedFiles(),
    };
  }

  function loadCells(args : Dynamic) : Dynamic {
    var world = editor.document.world;
    if (world == null) throw "Açık belge dünya değil (tek sahne)";
    var data = world.data, wanted : Array<Int> = [];
    if (args.cells != null) for (cell in (args.cells : Array<Dynamic>)) wanted.push(Std.int(cell));
    if (args.around != null) {
      var x : Float = args.around[0], y : Float = args.around[1], radius : Float = args.radius == null ? 0 : args.radius;
      var step = data.cellSize, sx = x - radius;
      while (sx <= x + radius + 1e-6) {
        var sy = y - radius;
        while (sy <= y + radius + 1e-6) {
          var cell = data.cellAt(sx, sy);
          if (cell >= 0 && wanted.indexOf(cell) < 0) wanted.push(cell);
          sy += step;
        }
        sx += step;
      }
    }
    if (wanted.length == 0) throw "cells ya da around gerekli";
    var loaded = [], already = [];
    for (cell in wanted) {
      if (cell < 0 || cell >= data.columns * data.rows) throw 'Dünyada böyle hücre yok: $cell';
      if (world.isLoaded(cell)) already.push(cell);
      else {
        world.load(cell);
        loaded.push(cell);
      }
    }
    return {loaded: loaded, alreadyLoaded: already};
  }

  function step(count : Null<Int>, back : Bool) : Dynamic {
    var steps = count == null ? 1 : count;
    var labels = [];
    for (i in 0...steps) {
      var label = back ? editor.commands.nextUndoLabel : editor.commands.nextRedoLabel;
      if (label == null) break;
      if (back) editor.commands.undo() else editor.commands.redo();
      labels.push(label);
    }
    editor.document.validate();
    return {done: labels, revision: editor.commands.revision};
  }

  function walkablePoint(x : Float, y : Float, radius : Float) : Dynamic {
    var nav = editor.scene.service(NavWorld);
    if (nav == null) throw "Yol ızgarası yok (dünya açık değil)";
    var ring = 0.;
    while (ring <= radius) {
      var count = Std.int(Math.max(1, Math.ceil(ring * 2 * Math.PI / SEARCH_STEP)));
      for (k in 0...count) {
        var angle = k * 2 * Math.PI / count;
        var px = x + Math.cos(angle) * ring, py = y + Math.sin(angle) * ring;
        if (nav.isWalkable(px, py)) {
          var at = place([px, py], false);
          return {position: [round(at[0]), round(at[1]), round(at[2])], distance: round(ring)};
        }
      }
      ring += SEARCH_STEP;
    }
    throw '$radius m içinde yürünebilir yer yok';
  }

  function path(from : Array<Float>, to : Array<Float>) : Dynamic {
    var nav = editor.scene.service(NavWorld);
    if (nav == null) throw "Yol ızgarası yok (dünya açık değil)";
    var points = nav.findPath(from[0], from[1], to[0], to[1]);
    var length = 0., previous = {x: from[0], y: from[1]};
    for (point in points) {
      length += Math.sqrt(Math.pow(point.x - previous.x, 2) + Math.pow(point.y - previous.y, 2));
      previous = point;
    }
    var end = points.length == 0 ? null : points[points.length - 1];
    var reached = nav.isWalkable(to[0], to[1]) && end != null && Math.abs(end.x - to[0]) + Math.abs(end.y - to[1]) < 2;
    return {reached: reached, startWalkable: nav.isWalkable(from[0], from[1]), length: round(length), points: [for (point in points) [round(point.x), round(point.y)]]};
  }

  function listModels() : Dynamic {
    var models = [];
    collectModels(RESOURCE_DIRECTORY, models);
    models.sort(Reflect.compare);
    var catalog : Dynamic = {};
    if (editor.actions.catalog != null) for (model in models) {
      var id = editor.actions.catalog.find(model);
      if (id != null) Reflect.setField(catalog, model, id);
    }
    return {models: models, catalog: catalog, notImported: editor.importer.pending()};
  }

  function collectModels(directory : String, found : Array<String>) {
    if (!FileSystem.exists(directory)) return;
    for (name in FileSystem.readDirectory(directory)) {
      if (StringTools.startsWith(name, ".")) continue; // Heaps'in .tmp önbelleği, Asset Browser da göstermez
      var path = '$directory/$name';
      if (FileSystem.isDirectory(path)) collectModels(path, found);
      else if (MODEL_TYPES.indexOf(Path.extension(name).toLowerCase()) >= 0) found.push(path.substr(RESOURCE_DIRECTORY.length + 1));
    }
  }

  // Asset Browser gibi: dönüştürme birkaç kare sonra başlar, tasarımcı durum satırında ne olduğunu görür.
  function importModel(args : Dynamic) : AgentReply {
    var source = modelSource(args.source);
    var file = settingsFile(source, args.folder);
    if (args.trim != null || args.clips != null || args.sockets != null || args.joints != null || args.length != null || args.grip != null || args.blender != null || args.skins != null) {
      if (file != null && args.trim != null) throw "trim klasör ayarına yazılmaz, yalnızca modelin kendi dosyasına (folder olmadan)";
      var settings = file == null ? ImportSettings.read(source) : ImportSettings.readFile(file);
      if (args.trim != null) {
        var boxes : Array<Dynamic> = args.trim;
        settings.trim = [for (box in boxes) ModelTrim.check(box)];
      }
      if (args.clips != null) {
        var clips : Array<Dynamic> = args.clips;
        settings.clips = [for (clip in clips) {
          var spec = ImportSettings.checkClip(clip);
          if (spec.source != "") spec.source = modelSource(spec.source);
          if (spec.arms != null) spec.arms = modelSource(spec.arms);
          spec;
        }];
      }
      if (args.sockets != null) {
        var sockets : Array<Dynamic> = args.sockets;
        settings.sockets = [for (socket in sockets) ImportSettings.checkSocket(socket)];
      }
      if (args.joints != null) {
        var map = new Map<String, String>();
        for (field in Reflect.fields(args.joints)) {
          if (scene.JointNames.STANDARD.indexOf(field) < 0) throw 'standart eklem adı değil: $field (${scene.JointNames.STANDARD.join(", ")})';
          var actual : Dynamic = Reflect.field(args.joints, field);
          if (!Std.isOfType(actual, String) || actual == "") throw 'eklem eşlemesi ad olmalı: $field';
          map.set(field, actual);
        }
        settings.joints = map;
      }
      if (args.length != null) settings.length = args.length == 0 ? null : ImportSettings.checkLength(args.length);
      settings.grip = flag(args.grip, settings.grip, "grip");
      settings.blender = flag(args.blender, settings.blender, "blender");
      if (args.skins != null) settings.skins = ImportSettings.checkSkins(args.skins);
      settings.write(source, file);
    }
    editor.show('Ajan modeli dönüştürüyor: $source. Büyük modellerde editör bir süre tepki vermez');
    var frames = IMPORT_WAIT_FRAMES;
    return {timeout: IMPORT_TIMEOUT, wait: function() : Null<AgentReply> {
      if (--frames > 0) return null;
      var result = editor.importer.run(source);
      for (problem in result.problems) editor.report(problem);
      if (result.target == null) {
        editor.show("İçe aktarılamadı, ayrıntı Uyarılar panelinde", true);
        throw result.problems.join("; ");
      }
      AssetImporter.forgetMissingFiles();
      editor.document.validate();
      editor.show('İçe aktarıldı: ${result.target} (${result.triangles} üçgen, ${result.parts} parça${result.trimmed > 0 ? ", " + result.trimmed + " üçgen kırpıldı" : ""})');
      var info = AssetImporter.infoPath(result.target);
      var sockets : Dynamic = FileSystem.exists(info) ? haxe.Json.parse(sys.io.File.getContent(info)).sockets : null;
      var path = result.target.substr(RESOURCE_DIRECTORY.length + 1);
      var catalog : Null<String> = null;
      if (editor.actions.catalog != null) {
        var reference = editor.actions.catalog.ensure(path);
        if (reference.command != null) editor.commands.execute(new GroupCommand('Ajan: katalog satırı ${reference.value}', [reference.command]));
        catalog = reference.value;
      }
      return {value: {source: source, path: path, catalog: catalog, triangles: result.triangles, parts: result.parts, trimmed: result.trimmed, clips: result.clips, sockets: sockets == null ? [] : sockets, problems: result.problems}};
    }};
  }

  // true / false ayarlar, "klasorden" kaldırır (klasör ayarı ya da hayır), verilmezse olduğu gibi.
  static function flag(value : Dynamic, current : Null<Bool>, name : String) : Null<Bool> {
    if (value == null) return current;
    if (value == true || value == false) return value;
    if (value == "klasorden") return null;
    throw '$name true, false veya "klasorden" olmalı: $value';
  }

  // folder: true en yakın klasör ayarı (yoksa kaynağın klasörü), metin kaynağın üst klasörlerinden biri; yoksa null.
  function settingsFile(source : String, folder : Dynamic) : Null<String> {
    if (folder == null || folder == false) return null;
    if (folder == true) {
      var found = ImportSettings.folderFiles(source);
      return found.length > 0 ? found[found.length - 1] : '${Path.directory(source)}/${ImportSettings.FOLDER_FILE}';
    }
    var directory = Path.removeTrailingSlashes(StringTools.replace(Std.string(folder), "\\", "/"));
    if (!StringTools.startsWith(source, directory + "/") || !StringTools.startsWith(directory, "assets")) throw 'folder kaynağın assets altındaki üst klasörlerinden biri olmalı: $directory';
    return '$directory/${ImportSettings.FOLDER_FILE}';
  }

  function modelInfo(args : Dynamic) : AgentReply {
    var source = modelSource(args.source);
    editor.show('Ajan modeli inceliyor: $source. Büyük modellerde editör bir süre tepki vermez');
    var frames = IMPORT_WAIT_FRAMES;
    return {timeout: IMPORT_TIMEOUT, wait: function() : Null<AgentReply> {
      if (--frames > 0) return null;
      var info = editor.importer.inspect(source, args.floorFraction);
      editor.show('İncelendi: $source');
      return {value: info};
    }};
  }

  function modelSource(wanted : String) : String {
    if (wanted == null || wanted == "") throw "source boş";
    var sources = editor.importer.sources();
    var needle = StringTools.replace(wanted, "\\", "/").toLowerCase();
    for (source in sources) if (source.toLowerCase() == needle) return source;
    var found = sources.filter(source -> source.toLowerCase().indexOf(needle) >= 0);
    if (found.length == 1) return found[0];
    if (found.length == 0) throw 'assets altında böyle bir model yok: $wanted. Modeller: ${sources.length == 0 ? "yok" : sources.join(", ")}';
    throw '"$wanted" birden çok modelle eşleşiyor: ${found.join(", ")}';
  }

  function checkRevision(expected : Null<Int>) {
    if (expected != null && expected != editor.commands.revision)
      throw 'Durum değişti: revizyon ${editor.commands.revision}, beklenen $expected. Yeniden oku (get_overview) ve tekrar dene. Hiçbir şey değişmedi.';
  }

  function titleOf(type : String) : String {
    var sample = editor.scene.registry.create(type);
    if (sample == null) throw 'bilinmeyen bileşen: $type';
    return sample.title();
  }

  function brief(entity : Entity) : Dynamic {
    var at = entity.object.getAbsPos();
    return {id: entity.id, name: entity.name, components: [for (component in entity.components) component.componentId()], position: [round(at.tx), round(at.ty), round(at.tz)], children: entity.children.length};
  }

  static function round(value : Float) : Float {
    return Math.round(value * 100) / 100;
  }
}
