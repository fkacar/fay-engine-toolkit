"""Bir modeli Blender'dan gecirip FBX yazar (Heaps 2.1 yalnizca FBX okur). Editorun ice aktaricisi baslisz cagirir:
  blender -b --factory-startup --python blender_fbx.py -- <kaynak> <cikti.fbx>
Kaynak: GLB, glTF, OBJ ya da FBX. FBX'i yeniden gecirmek, baska bir aracin olcegiyle (FBX_SCALE_NONE: kemikler 100 kat)
ya da sabit olmayan kare hiziyla yazilmis dosyalari duzeltir: cikti FBX_SCALE_UNITS ile yazilir, klipler sahnenin kare
hizina pisirilir. Dokular FBX'in icine gomulur; ice aktarici onlari yanina cikarir. Cikti turetilmis dosyadir, depoya girmez.
"""
import os
import sys

import bpy


def name_images():
    # Paketli resimlerin (GLB) adi uzantisiz gelir ("Image_1"); ice aktarici uzantisiz dokuyu atar.
    seen = set()
    for image in bpy.data.images:
        if image.source != "FILE" and not image.packed_file:
            continue
        ext = ".jpg" if image.file_format == "JPEG" else ".png"
        base = os.path.splitext(os.path.basename(image.filepath or image.name))[0] or image.name
        base = "".join(c if c.isalnum() or c in "-_" else "_" for c in base)
        name = base + ext
        n = 2
        while name in seen:
            name = f"{base}_{n}{ext}"
            n += 1
        seen.add(name)
        image.name = name
        image.filepath_raw = "//" + name


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    source, target = args[0], args[1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lower = source.lower()
    if lower.endswith((".glb", ".gltf")):
        bpy.ops.import_scene.gltf(filepath=source)
    elif lower.endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=source)
    elif lower.endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=source)
    else:
        raise SystemExit(f"desteklenmeyen kaynak: {source}")
    name_images()
    bpy.ops.export_scene.fbx(
        filepath=target,
        use_selection=False,
        apply_scale_options="FBX_SCALE_UNITS",
        path_mode="COPY",
        embed_textures=True,
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_all_actions=True,
        bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True,
        # Sadeleştirme kapalı: her karede anahtar. Heaps boşluklu eğrileri doldururken kayan nokta birikimiyle
        # "not baked on a fixed framerate" hatası verebiliyor (seyrek anahtarlı bir ölüm klibinde görüldü).
        bake_anim_step=1.0,
        bake_anim_simplify_factor=0.0,
    )
    print("BLENDER_FBX_TAMAM", target)


main()
