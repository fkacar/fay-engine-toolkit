package scene.editor;

// Nesne yerine hücre verisini değiştiren komut: arazi ve dağıtma fırçaları.
interface CellCommand {
  function touchesCell(cell : Int) : Bool;
}
