package scene.editor;

import scene.Entity;

// Sahnedeki her değişiklik bir komut nesnesidir, undo ve redo bunun üzerine kuruludur.
interface Command {
  var label(default, null) : String;
  function execute() : Void;
  function undo() : Void;
  // Değiştirdiği nesneler. Hücre boşaltılınca o hücrenin adımları buna göre düşer.
  function touched() : Array<Entity>;
}
