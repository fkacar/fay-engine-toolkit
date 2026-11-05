# Fay Engine Toolkit

Shared scene infrastructure and editor for our 3D games written in Haxe + Heaps.

Türkçe: [README.tr.md](README.tr.md)

| Folder | Contents | Used by |
|---|---|---|
| `runtime/` | Scene format, component model, persistent IDs, the `@:editable` macro | Game and editor |
| `editor/` | Docking shell, Hierarchy, Inspector, command system | Only the `-D scene_editor` build |
| `tests/` | Tests | None |
| `template/` | Starter project for a new game | New projects |
| `tools/` | Scripts for running, building `hlimgui` and creating projects | None |
| `vendor/hashlink/` | Pinned HashLink libraries for Mac | Mac build |
| `third_party/hlimgui` | Dear ImGui binding pinned to a commit | Editor |

The editor's interface is in Turkish. Where this document names a menu, panel or button, the Turkish name is given as it appears on screen, with an English gloss.

## New game

```sh
sh libs/scene-toolkit/tools/new-project.sh ../new-game
cd ../new-game
./run.sh editor
```

The template adds the toolkit under `libs/scene-toolkit` as a git submodule and pins it to the commit you are on.

The toolkit and the game are pushed together with `./push.sh "message"`; the order is not managed by hand. See the comment at the top of `tools/push.sh` for details.

## Adding it to a game

Games add this repository as a submodule at `libs/scene-toolkit`. Clone with `git clone --recursive`. For changes pulled later, run `git submodule update --init --recursive`.

## Writing a component

```haxe
@:component("house")
class HouseComponent extends Component {
  @:editable("Height", 2, 12) public var height : Float = 4;

  override function onCreate() {
    // Build the visuals. Runs in the game and in the editor.
  }

  override function onUpdate(dt : Float) {
    // Runs only in the game.
  }
}
```

A component is registered with `ComponentRegistry.register`. The field type must be written out: `Float`, `Int`, `Bool`, `String`, `Array<String>` or `Array<Float>`.

If a text field's meaning is marked, the Inspector shows a suitable input and save validation checks it:

```haxe
@:editable("Model") @:asset public var path : String = "";     // Dragged from the Asset Browser; the file is checked
@:editable("Target") @:entity public var target : String = ""; // Picked from a list; the object is checked
@:editable("Part") @:prefab public var part : String = "";     // Picked from the prefab list; the file is checked
@:editable("Kind") @:choice("easy", "hard") public var kind : String = "easy";  // Drop-down list
@:editable("Color") @:color public var tint : Int = 0xFF8000;  // Color picker
```

Table and dialogue fields:

```haxe
@:editable("Faction") @:ref("factions") public var faction : String = "neutral";  // res/data/factions.table.json
@:editable("Dialogue") @:dialog public var dialog : String = "";                  // res/data/dialogs/<id>.dialog.json
```

A row missing from the table, or a missing dialogue, gives a compile warning but does not stop the build; in the editor it shows in the **Uyarılar** (Warnings) panel. These are content, not code: a designer deleting something, or two people merging, must not leave the team's editor unable to open. The data panel blocks deleting a row that is in use and changing its ID (`scene.editor.DataUsage`). Mismatches on the code side (components, fields and `@:choice` options) still stop the build.

A component reports its quest links with `storyLinks()` (`scene.story.StoryLink`): it waits for or emits (event), reads or sets (variable), requires, gives or takes (item), starts (dialogue). The Warnings panel and the agent's `explain_quest` tool match these up. A component gives its display name with `title()`, its "Bileşen ekle" (Add component) group with `category()`, and its own rules for the Warnings panel with `issues()`. If `addable()` returns group names, the Inspector shows "+ Group" buttons under the component; the trigger returns `[TriggerCondition.CATEGORY, TriggerAction.CATEGORY]`.

A `@:choice` field must be a `String` and its default must be one of the options. If an option is removed from the code, any scene, prefab or prefab override that uses that value stops the build.

A component whose visuals are not under `entity.object` (such as a unit attached to the scene root) returns them from `visuals()`. Selection and hiding cover these visuals too.

Shapes that are not visible in the game are drawn in `drawOverlay(overlay, selected)`. Ready-made shapes are in `OverlayShapes`.

## Writing a marker

A marker is a component that is invisible in the game and clickable in the editor. It extends `Marker`, is registered with `ComponentRegistry`, and appears in the `Düzen > İşaretçi ekle` (Edit > Add marker) menu by itself:

```haxe
@:component("camp")
class CampMarker extends Marker {
  @:editable("Radius", 1, 100) public var radius : Float = 8;

  override public function color() : Int {
    return 0xE08040;
  }

  override public function title() : String {
    return "Camp";
  }

  override function drawShape(overlay : Overlay, tint : Int, at : h3d.Vector) {
    OverlayShapes.circle(overlay, flatFrame(at), radius, 0, tint);
  }

  override function onStart() {
    // Runs when the game starts. Does not run in the editor.
  }
}
```

For a route, extend `RouteMarker` and also register `WaypointMarker`. The points are child objects; `waypoints()` returns them in order. For the `collider` component, register `ColliderComponent`.

A game that knows the ground height calls `level.provide(GroundHeight, terrain)`; markers then sit on the ground and `z` becomes the height above it. Without it, `z` is used as is.

## World

The world is optional. A game that works with a single scene skips this section. The data and the tools are in the toolkit; drawing belongs to the game, because the look changes from game to game.

```
res/world/main.world.json      grid, terrain layers
res/world/global.scene.json    objects not tied to a cell
res/world/environment.json     time of day, sun, fog
res/world/c_3_2.scene.json     the cell's objects, same format as a scene
res/world/c_3_2.terrain.json   height and paint
res/world/c_3_2.scatter.json   scattered objects
res/world/c_3_2.nav.json       navigation mesh
res/world/c_3_2.terrain.mesh   the part of the terrain model that falls in this cell, binary (LFS)
res/world/textures/            textures of the terrain models
```

To hook it up:

1. The game implements the `WorldView` interface: drawing terrain and scatter, scatter types, weather presets, applying the environment.
2. The game builds a `WorldState` with `WorldData.read` and sets `state.view`.
3. In the editor: `state.loadAllTerrain()` and `new Editor(level, "res/world/main.world.json", state)`.
4. In the game: `new CellStreamer(state, level, true)`, `start(x, y)` and `update(x, y)` every frame.
5. For the build check, add `--macro scene.macro.SceneCheck.run("res/world")` to `common.hxml`.

The editor has no command for creating a new world; the first `main.world.json` is written by hand. A missing terrain file counts as flat terrain and is created on the first save.

Components take part in the world in two ways:

```haxe
// An area of the navigation mesh that cannot be walked
override public function navShapes() {
  return [NavShapes.box(entity.object.getAbsPos(), width, depth)];
}

// Something that left its cell and came near the player should not be removed with the cell
override public function keepsCell(isNear : (Float, Float) -> Bool) {
  return Lambda.exists(units, unit -> isNear(unit.x, unit.y));
}
```

`CellStreamer` loads cells within the `objectRadius` ring and unloads a cell once it is one cell outside. Terrain stays within the `terrainRadius` ring. `onStart` also runs for cells that arrive while the game is running.

The terrain model comes from an FBX under `assets/terrain/`. The FBX is converted to HMD under `.editor/terrain/` and does not go into the repository. Triangles are split into cells by their centroid and are not cut. Height is written at a 2 metre spacing into the cell's `.terrain.json`, and squares whose four corners the model covers become `TerrainCell.COVERED`. The game does not draw its own terrain on these squares; it draws the part through `state.surfaces` in `WorldView.terrainChanged`. When the model is applied again, each cell is compared with the old one and only the cells that differ go into the command. `*.mesh` must be in LFS in `.gitattributes`. Heaps mirrors FBX on the X axis; the model follows this rule like buildings do.

Pathfinding is done with `NavWorld.findPath`. It is a node grid per cell, pure Haxe, and needs no native library. Cells are read the first time they are needed; a cell without a navigation mesh counts as walkable. If we move to Recast, `NavWorld` and `NavBaker` change and components are not affected.

## Quests and dialogues

This is the `scene.story` package. The game builds a `Story` and provides it with `level.provide(Story, story)`; the game state (`GameState`: items, variables, faction relations), the open dialogue and named events live there.

- A condition is a component that extends `TriggerCondition`, an action one that extends `TriggerAction`. They are added to a trigger object; `story.fire(entity)` runs the actions in component order if all conditions hold.
- A dialogue is in the `Dialog` format and is played by `DialogRunner`. An event node calls `story.emit(name)`, and a trigger waiting with `story.listen(name, entity)` runs. This keeps item and variable logic in one place, in the actions.
- Drawing the dialogue box belongs to the game: read `story.dialog`, call `next()` and `choose(i)`.
- In the editor a dialogue is edited in place of the scene view with `scene.editor.DialogWorkspace`; the selected node opens in the Inspector. `DialogPanel` in the bottom panel is only a list.
- Node positions are stored in units independent of screen density and are multiplied by `interfaceScale` for the canvas. Auto layout (`scene.story.DialogLayout`) works from the content, not from sizes measured on screen: a Retina Mac and Windows produce the same file.
- "Tetikleyici ekle" (Add trigger) is found from the registered components: a placeable marker with an action group in `addable()`, and a `TriggerAction` with a `@:dialog` field. If either is missing, the button is hidden.
- If the game names the item table with `editor.dialogs.itemTable`, items are picked from a list in condition nodes, and dialogues are also scanned when a row is deleted.

Game data is read with `scene.data.DataTable` and `GameData`. Each table is a `res/data/<name>.table.json` file.

## File safety

The editor never writes a file blindly (`DiskGuard`, `StoreGuard`):
- Before saving it reads the disk again. If the file changed outside, it does a three-way merge with `scene.data.ThreeWay`: per object in a scene, per row in a table, per node in a dialogue.
- If the same unit changed differently on both sides, it does not write the file. It backs up both versions under `.editor/catismalar/` (conflicts) and lets you choose in the Warnings panel.
- It polls open files once a second. It reloads a clean one and drops that file's undo steps with `CommandStack.forget`.

Code that writes a new kind of file must go through this path.

## Agent server

`scene.editor.agent.AgentServer` opens an MCP (HTTP) server on `127.0.0.1:8890` when the editor starts. The socket is polled every frame and tools run on the main loop. An error in a tool does not bring the editor down; it goes back to the agent as an error. Requests with an `Origin` header or another `Host` are rejected.

`ContextTools` registers read-only context tools and prompts (`addPrompt`). `PlayTools` registers the game view, `EditTools` the write tools, and `ExamTools` the agent exam (`tests/ajan-sinavi/*.sinav.json`). The game adds its own tools with `editor.agent.add` and can call another tool with `callTool`. `AgentPanel` shows the latest calls (`agent.log`).

**Model import:** Before converting an FBX to HMD, `AssetImporter` aligns the animation curves with `FbxCurves.sync`. Heaps reads a node's X, Y and Z curves at the key times of the first curve, so keys reduced axis by axis fell to zero. Settings live next to the source in `<name>.aktarim.json` (`ImportSettings`: `trim`, `clips`, `sockets`, `joints`, `length`, `grip`, `blender`). A `klasor.aktarim.json` in a folder applies to every model in its subfolders (`ImportSettings.effective`); the model's own file overrides the clip, socket and field of the same name, and trimming only comes from the model itself.
- `BlenderConverter` converts GLB, glTF and OBJ (and FBX too if the setting has `blender: true`) to FBX with headless Blender (`tools/blender_fbx.py`: `FBX_SCALE_UNITS`, embedded textures, a key on every frame). The output goes under `.editor/donusum/` and is refreshed when the source or the script changes. Blender is found from the `BLENDER` environment variable or from the known install locations on Mac and Windows.
- `scene.JointNames` (runtime) maps joint names to standard names: Mixamo, the `mixamorig:` prefix, Rigify (`DEF-`, `ORG-`). Import writes the mapping into the `joints` field of `<name>.model.json`; the game looks joints up with the same mapping, so a new skeleton needs no code change.
- Multi-clip FBX: a clip row's `take` field is the clip's name in the file (matched from the end); if `source` is empty, the clip comes from the model's own file.
- `skins` is a pattern relative to the source for alternative textures (`textures/{name}_skin*.png`); matching textures are copied next to the model and their names are written into the `skins` field of `<name>.model.json`. At runtime `ModelLibrary.texture(path)` returns the texture.
- For a model without a skeleton, `length` scales the longest side to metres (`RigidModel.scaleTo`), and `grip: true` estimates the grip point from the vertices (`GripEstimate`: main axis, the thin end is the handle, X is the head's widest direction).
- `ModelTrim` trims triangles with boxes. A triangle is collapsed to a single point, so vertex and skin data stay intact.
- `ModelClips` adds clips from other FBX files to the HMD, retargets them to the rig's rest pose (`retarget`) and measures the stride speed.
  - Clips are read with a separate `HMDOut`; `leftHandConvert()` must be called before `loadAnimation()`, otherwise rotations are not mirrored and the arms swap places.
  - If a clip row has `arms`, the arm joints (from the collarbone to the hand) stay fixed at that clip's first frame (`holdArms`): this is how armed clips missing from the library are derived.
- Sockets (`ImportSettings.sockets`) are written into `<name>.model.json`; for a model with a skeleton and no setting, defaults are placed on the standard joints (through the mapping; the palm from the vertices bound to the hand). The axis follows the body in the bind pose, and its direction is `socketFrame`. For a model without a skeleton, only the points are written.
- In data tables, the `varlik` (asset) type is a file path under `res/`. `GameData.forget` drops the cache when a table changes.
- `Editor.requestRender` performs one off-screen render inside the drawing frame (the game's agent preview draws with this).
- Saving (`scene.save`, general parts the game uses; the game decides what to store):
  - `Saveable`: returns a component's difference and restores it.
  - `WorldDelta`: the differences of closed cells. Once `SceneInstance.delta` is set, `destroyEntity` takes the difference, and `stream` and `start` restore it before `onStart`.
  - `SaveFile`: a sectioned, compressed file with CRC32; safe writing and a backup.
  - `SaveSlots`: campaigns and slots.
  - `PlayOptions.save` (`--save`), `CellStreamer.restart`, `GameState.watch` and `restore`.
  - `Random`: a seeded generator, an exact copy of `hxd.Rand` (a Heaps update cannot change the numbers that come out of a seed; locked with golden values in the tests). `Math.random`, `Std.random` and `hxd.Rand` are banned in code, and a guard test scans for them. `RandomStreams`: named, saveable streams from the campaign's seed.
  - To destroy in the game, use `SceneInstance.removeEntity` (recorded as "removed" in the difference; not built when the cell opens). To build in the game, use `spawnEntities(data, cell, owner)` (the full data goes into the save and opens and closes with the cell). `destroyEntity` is for closing a cell and does not record "removed". IDs come from `WorldDelta.newId(stream)`.
  - Play from save: `SaveInspector` (the game provides the save list and the report), `panels/SavesWindow` (`Oyun > Kayıttan oyna…`, Game > Play from save…), `Editor.playFromSave`, and the quest test's `save` field (a game opened with `--save`). In an exam task, `files` (puts the task's files in place and removes them at the end) and `save: true` for `quest_test`.
  - Saving without a freeze: `SaveFile.pack` / `encodePacked` (compressed sections), `DeltaSections` (cell sections are cached; `WorldDelta.touch`/`takeDirty` track changed cells and only those are encoded again), `SaveWriter` (a background thread: writes in order, prepares `later` sections there, `poll`/`flush`). `SaveSlots.AUTO_COUNT` is 5.
  - Optimization engine (`scene.tune`; the game's plan is `docs/OPTIMIZASYON_PLANI.md`): `TuneModule` (tunables, locked tunables, metrics `Max`/`Min`/`Band`/`Limit`, scenario, training and validation seeds, source `sentetik` (synthetic) or `iz` (traces)), `Tuner` (brute force, or random sampling and local improvement; a cache; a choice that also keeps hard limits on validation; the quality–performance frontier), `TuneReport` (Markdown report).
  - Versions: `Migrations` (format migrations in order; the game adds steps), `ContentPrint` (CRC32 fingerprint of cell files and tables; `diff` returns what changed after the save), `WorldIndex` (every designed object, with prefab contents expanded; for orphaned differences and their replacement candidates).
  - What survives a reset: `WorldDelta.isPlayerOwned` (`owner: "oyuncu"` (player) in the component state, or built by the player) and `isStory` (`story: true` in the state, story progress such as a trigger that has run). `forgetCell` (region reset) keeps these, and `importPart` (Import) moves only these.
  - `WorldDelta.remap`: ID mapping. In the editor, `ReleaseIds` writes the release list, warns about a release object that has gone missing, suggests the one that replaced it and maps it into the `kayit_esleri` table. The release list only grows; mappings chain (`ReleaseIds.resolve`, `WorldDelta.remap`), and an object removed on purpose is let go (the `birak` column). `Issue.actions` draws buttons next to a warning.
  - Retargeting: for each joint, rig world = rig rest × clip rest⁻¹ × clip world. Bone lengths come from the rig.
  - A clip's skeleton comes from one reader and its frames from a separate reader. If Heaps calls `loadAnimation` a second time on the same reader, it converts the angles to radians again.
  - Frames are written with `HMDOut.makeAnimation`.
- For a model with a skeleton, `<name>.model.json` is written next to it: height, hip position and clip speeds in metres, and the facing direction (opposite to the foot that is on the ground while walking).
- If the settings file or a clip's source is newer than the HMD, the model goes on the list to be imported again.
- At runtime `ModelLibrary.animation(path, name)` returns the named clip from the cache.
- Import drops the model it wrote from `ModelLibrary` and notifies listeners at once with `AssetWatch.changed`. An old header left in the cache reads the new file wrongly, causing a null access in the skin.
- Agent tools: `model_info` (bounds, joints, joint mapping, clip names in the file, clips, character info, effective settings, floor map), and the `trim`, `clips` (with `take`), `sockets`, `joints`, `length`, `grip`, `blender` and `folder` (writes the folder setting) fields of `import_model`. Write tools use editor commands and record the call as a single history step (`CommandStack.record`). On an error, the commands already applied are undone. For screenshots, the game's `Main.render` must call `editor.afterRender(e)` after `super.render(e)`; the template does this. The game adds its own tool with `editor.agent.add({name, description, schema, readOnly, run})`. `run` returns an object: `{value}` goes as JSON, `{text}` as plain text, `{png}` as an image. The project's `.mcp.json` and `.claude/settings.json` sit in the template as `mcp.json` and `claude-settings.json`, and `new-project.sh` puts them in place. The `PostToolUse` hook in `settings.json` runs `tools/agent-hook.sh`. The script reads `.editor/ajan-durum.json` (agent status), which the editor writes every two seconds. If the editor is closed, it stays silent and never connects to the server, so no error message appears while the editor is closed.

## Game view and quest tests

For F5 or a quest test, the editor opens the game in a separate process with `--play`. They communicate through files (`scene.PlayFiles`):
- The game writes its state to `bin/ajan/oyun-durumu.json` (game state) and the story trace to `bin/ajan/oyun-izi.jsonl` (game trace).
- In a quest test the editor writes `bin/ajan/senaryo.json` (scenario). The game reads it, plays it, writes `bin/ajan/sonuc.json` (result) and closes.

For the trace, the game sets `story.log = new scene.story.StoryLog()`; Story and `DialogRunner` record their own steps.

The bridge that writes the state and the runner that plays the test steps belong to the game, because the squad and units are the game's own types. In our game they are in `src/agent/PlayBridge.hx` and `QuestTestRunner.hx`. As long as another game writes the same files, the editor and the agent tools work unchanged. Quest tests are in `res/tests/*.test.json`; the format is in the game's editor guide.

## Prefab

A prefab file is `res/prefabs/name.prefab.json`, a small scene with a single root. The scene keeps only the root row: the `prefab` path and the `overrides` list. Children are expanded on load, and their IDs have the form `root/part`. Differences are not tracked by hand; they are found on save by comparing with the prefab.

Before loading the scene, the game provides the file reader:

```haxe
level.prefabLoader = path -> hxd.Res.load(path).toText();
```

For the build check, add `--macro scene.macro.SceneCheck.run("res/prefabs")` to `common.hxml`. An override pointing to a field that is no longer in the code stops the build. A missing prefab file or a prefab with two roots is content: the build warns and does not stop, and `push.sh` shows the warning before asking for confirmation. A prefab that cannot be opened does not break the scene: in the editor the root keeps its path and overrides, in the game it is built as an empty object and a `Sahne uyarısı` (scene warning) is written.

## Renaming

The file stores the `@:component` ID, not the class name, so moving or renaming the class does not affect scenes.

If an ID or an `@:editable` field name changes, the old one is declared. Scenes open with the old name and switch to the new one on the first save:

```haxe
@:component("house")
@:formerly("hut")
class HouseComponent extends Component {
  @:editable @:formerly("h") public var height : Float = 4;
}
```

If the declaration is forgotten, the build stops and says which object in which scene is affected. For this, the game's build settings must have this line:

```
--macro scene.macro.SceneCheck.run("res/scenes")
```

If a component or field was removed on purpose, the scene file is updated too.

`@:choice` options have no former-name declaration. If an option is removed or renamed, the build stops; change the values under `res/scenes/` and `res/prefabs/` in the same commit.

## Scene file

It is JSON and is written deterministically: the same scene produces the same file on every system. Numbers are rounded to 5 decimals, rotations are in degrees, and fields are sorted alphabetically. Components and fields this build does not recognize are not deleted; they are written back as they were.

A prefab instance's row has `prefab` and `overrides`; these fields are not written for objects that are not instances.

If the format changes, `SceneFormat.VERSION` is raised and an upgrade is added to the `MIGRATIONS` list.

## Hooking the game up to the editor

The template's `Main.hx` is a ready example. Everything specific to the game is registered at startup:

```haxe
editor = new Editor(level, "res/" + MAIN_SCENE);
editor.actions.groundRay = ray -> terrain.raycast(ray);        // Without it, the z = 0 plane
editor.actions.addAssetType("fbx", "model", "path");           // Which component a dragged file is written to
editor.validator.rules.push(scene -> myIssues(scene));         // A game rule that runs on save
editor.addPanel("Factions", drawFactions);                     // A game-specific panel
```

- Call `editor.render(e)` in `Main.render`; model previews are drawn there.
- Frame guard (`scene.editor.FrameGuard`): when an editor frame is cut short, Dear ImGui stops the application at the next `NewFrame` (assert, abort) and unsaved work is lost. The application hooks up four places; the template's `Main.hx` is an example:
  - `FrameGuard.install()` in `init`: Heaps' error reporting is wrapped and the error text is kept.
  - `FrameGuard.beforeFrame()` at the start of `mainLoop`, with the result passed to `editor.frameFailed`: if the previous frame was cut short, ImGui is recovered.
  - The body of `update` runs inside `FrameGuard.run`, with the error passed to `editor.failed`.
  - In `render`, scene drawing is inside a `try`, with the error passed to `editor.renderFailed`: render targets are released and the ImGui interface is still drawn.
  - The editor draws its own sections and every panel with `FrameGuard.run`. A panel that fails stays stopped until "Yeniden dene" (Try again). The error appears in the notification, the Warnings panel, the log and the agent's `get_warnings` tool, and the scene is backed up at once (`SceneDocument.backupNow`, at most once every 10 seconds).
  - The native side, `editor/native/imgui_guard.cpp`, is compiled into the hlimgui extension. Third-party hlimgui is not touched: on Mac `tools/build-hlimgui.sh` adds it to the source list, and on Windows the `tools/hlimgui/CMakeLists.txt` wrapper adds it to the same target.
  - When the extension changes, `tools/hlimgui-surum.txt` (version) goes up. The build scripts write the stamp next to the hdll; `run.sh editor` and `run.bat editor` recognize an old hdll and say to rebuild it. An old hdll lacks the new native functions, and HashLink would report that at startup with an obscure error.
- The editor binary opens as the game with `--play <scene> --camera x y z x y z`, which `PlayOptions.parse(Sys.args())` reads. "Buradan oyna" (Play from here) uses this, because the game build carries its resources embedded and does not see a newly saved scene.
- Personal settings are under `.editor/` and do not go into git: recently opened files, what is hidden in the editor, automatic backups.
- Visibility is two separate states. `entity.active` is written into the scene and affects the game; `entity.hiddenInEditor` only applies on that computer. They are independent: an object turned off in the game stays editable in the editor.
- Import writes a model under `assets/` (FBX; GLB, glTF and OBJ converted with Blender) as HMD under `res/models/`; those under `assets/models/mock/` go under `res/models/mock/`. It can be called without the editor interface: `new AssetImporter().run(source)`. The game build converts FBX inside a macro and needs `meshTools` for a model with a normal map; HMD has no such step. A new game's `.gitattributes` must have `*.hmd` in LFS.
- Heaps' normal map and specular shaders take the UV from the base color texture. A material without a base texture fails when drawn, so the importer adds a 1x1 white texture to such materials. A missing texture also drops the whole model in Heaps, so it is removed from the model with a warning.
- Selection looks at mesh triangles. Heaps cannot produce collision data for a non-indexed `Polygon`, so `Picker` scans these with its own triangle test. If a new primitive type cannot provide `getCollider`, the picker falls back to the bounding box, and a large box swallows every click.
- `ModelLibrary.load` returns models from a single cache, and copies share geometry and textures. Components must not open a `ModelCache`.
- A model reference is a catalog ID or a file path (`scene.ModelRef`). The game gives its catalog to `ModelRef.catalog` (ID → file); `ModelLibrary.load`, `animation` and `exists` accept a reference. An ID is `[a-z0-9_]`, while a path contains `/` or an extension; paths in old content keep working. `ModelRef` does not depend on Heaps.
- If `editor.actions.catalog` (`{find, ensure}`) is given in the editor, the catalog ID is written into the field of a file dropped into the scene; if there is no row, `ensure`'s table command goes into the same undo step as the object. Import (the Asset Browser and the agent's `import_model`) also adds the row; `import_model` returns the ID as `catalog`, and `list_models` gives the files' IDs. `editor.data.onApplied` is called right away every time a table is applied (edit, undo, agent); if the game clears its cache there, a read in the same frame sees the new table.
- `SceneInstance.observers`: the game's systems (such as physics) listen for objects starting in the game (after their components start) and for their removal (before their components close). Only in play mode, once the scene has started.
- Import from the command line: `./run.sh ice-aktar <file or folder>` (import; `scene.editor.ImportMain`, `import-mac.hxml`; on Windows, `import.hxml` for bytecode). It opens no window and uses the same `AssetImporter.run` as the editor; every model in a folder is imported. The game adds the catalog row.
- The collider component (`ColliderComponent`) is data only; if the game's physics service provides `ColliderComponent.bridge` (`added`, `removed`, `moved`), the component reports when it starts in the game (`onStart`), when it is removed and when it moves. A service connected later builds the loaded terrain cells with `WorldTerrain.loaded()` and gets the rest through `WorldView.terrainChanged`.
- `FocusGuard.install()` releases keys when focus is lost. Heaps does not, so a key stays pressed after Cmd+Tab or Alt+Tab. The editor installs it itself; the game calls it in `init`.
- On Mac, HL/C is compiled with clang at `-O2 -g` (about 7 times faster than `-O0`, and the build takes a few seconds longer), and `-fwrapv` is required: Haxe's Int wraps on overflow, while signed overflow is undefined in C. At `-O1` and above, hash and random number loops break without it (the FNV seed came out as 0 for every string). `tools/run.sh` passes the flag; add it to your own build script too.
- The Heaps camera is left-handed: the right of the screen is counterclockwise from the view direction. Test camera directions by where a point goes on screen, not by their own vectors.
- Heaps drops the horizontal wheel value. The patched `hxd.Window` on Mac keeps it in the `horizontalWheel` field, which is how Option + two fingers rotates. Windows does not have this value; there Ctrl + two fingers rotates. `hlsdl` truncates both values to integers, so very slow scrolling below 1 is lost.
- Colors in the ImGui draw list are in `0xAARRGGBB` format.
- The hlimgui binding has two traps: `selectable` crashes with a constant `true`/`false`, so pass the value through a variable. `getColorU32(ImGuiCol.X)` returns transparent; use `getStyleColorVec4`.

## High DPI (Retina and Windows scaling)

Builds draw at real pixel size with `hidpi.hxml`: Retina on Mac, and display scales such as 125%, 150% and 200% on Windows. Heaps does not support this, so `hidpi/hxd/Window.hl.hx` is a patched copy of the Heaps 2.1.0 file. hlsdl 1.16 uses SDL3, and the two systems behave differently (SDL3 README-highdpi):

| | Window coordinates | `pixelDensity` | `contentScale` (display scale) |
| --- | --- | --- | --- |
| Mac Retina | points | 2 | 2 |
| Windows 150% | pixels | 1 | 1.5 |

- `hidpi.hxml` must come before `common.hxml` in every `.hxml` file (Mac and Windows). If it comes after, Haxe picks Heaps' own file and the build fails with a `pixelDensity` error.
- The patch converts between points and pixels only on Mac (`pixelDensity`); on Windows the window is already in pixels. The interface's scale factor is `contentScale` on both.
- `HiDpi.prepare()` is called in `main`, before SDL starts: on Windows the process becomes per-monitor DPI aware (`SDL_WINDOWS_DPI_AWARENESS=permonitorv2`), so the operating system does not blur-scale the image.
- The game calls `HiDpi.fit(s2d, minimumHeight)` in `init`. `s2d` keeps its old units, while `s3d` and `engine.width` are in real pixels. `HiDpi.density` is the scene's scale: the game's choice (`HiDpi.choice`, then `HiDpi.refresh()`), otherwise the display's scale; it is reduced if the scene would be shorter than the given height.
- The window size is chosen in unscaled units and multiplied by `HiDpi.displayScale` for the pixel size; when comparing with the desktop size, use `displayScale / pixelDensity` (1 on Mac, the scale on Windows). A window that grows with the scale can exceed the desktop (on a 1080p display at 150%, 1280x720 → 1920x1080): the game should shrink it enough to fit with the title bar and taskbar, and the minimum height given to `fit` still fits the interface.
- The editor does not zoom the `imguiScene` scene, because hlimgui clips in raw pixels. Fonts and style grow with `HiDpi.density`.
- Fixed-size bitmap fonts are scaled up with smoothing in `s2d`. Staying sharp needs a 2x atlas; above scale 1, drawing the 2x atlas at half scale (scaling it down) stays sharp.
- The Windows behavior was built from the documentation (SDL3) and has not been tried on Windows.
- When Heaps is upgraded, the patch is applied again to the new file; the changed lines are marked with `HiDPI`.
- In a Mac `.app` bundle, `NSHighResolutionCapable` must be enabled in `Info.plist`.

## Tests

Quick check, from the project root: `haxe libs/scene-toolkit/tests.hxml`. Tests that need Heaps' math types (`h3d.Vector`, `h3d.Matrix`) are separate: `haxe libs/scene-toolkit/tests-heaps.hxml` (`tests/heaps`). The interpreter cannot compile Heaps' model data (`hxd.fmt.hmd`), so the code there does not depend on it.

On the real target, HashLink: `./run.sh test` or `run.bat test`. Number and type behavior can differ from the interpreter, so this is the one that counts.

## License

The toolkit is under the MIT License, the same license as Heaps: [LICENSE](LICENSE).

Bundled third-party parts keep their own licenses:

- `vendor/hashlink/`: [HashLink](https://github.com/HaxeFoundation/hashlink) libraries, MIT License ([HashLink license](https://github.com/HaxeFoundation/hashlink/blob/master/LICENSE)). `libopenal` is [OpenAL Soft](https://github.com/kcat/openal-soft), LGPL 2.1 ([OpenAL Soft license](https://github.com/kcat/openal-soft/blob/master/COPYING)).
- `hidpi/hxd/Window.hl.hx`: a patched copy of a [Heaps](https://github.com/HeapsIO/heaps) file, MIT License ([hidpi/LICENSE_HEAPS](hidpi/LICENSE_HEAPS)).
- `editor/fonts/`: DejaVu Sans Mono ([editor/fonts/LICENSE_DEJAVU](editor/fonts/LICENSE_DEJAVU)).
- `third_party/hlimgui`: the [hlimgui](https://github.com/nspitko/hlimgui) submodule, under its own license.
