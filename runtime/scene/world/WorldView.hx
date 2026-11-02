package scene.world;

// Dünyanın çizimi oyuna aittir: görsellik oyundan oyuna değişir, veri ve araçlar değişmez.
typedef ScatterType = {
  var id : String;
  var title : String;
  var radius : Float;  // ölçek 1'de yürünemeyen yarıçap, 0 ise içinden geçilir
}

interface WorldView {
  function scatterTypes() : Array<ScatterType>;
  function weatherPresets() : Array<scene.world.EnvironmentData.WeatherPreset>;
  function environmentChanged() : Void;
  function terrainChanged(cell : Int) : Void;
  function terrainRemoved(cell : Int) : Void;
  function scatterChanged(cell : Int) : Void;
  function scatterRemoved(cell : Int) : Void;
}
