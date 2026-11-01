package scene.editor;

// Sahnedeki her değişiklik bir komut nesnesidir, undo ve redo bunun üzerine kuruludur.
interface Command {
  var label(default, null) : String;
  function execute() : Void;
  function undo() : Void;
}
