"""Build Milo v2 from Blender Studio Snow and selected mocap sources.

Run:
  MILO_ASSET_ROOT="/path/to/milo" Blender -b --factory-startup \
    --python Scripts/milo/build_all.py -- /absolute/path/to/LangLearn
"""
from __future__ import annotations

import json
import math
import shutil
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).parent))
from sources import repository_root, safe_output, verified_sources
from face_export import bake_face


ROOT = repository_root(sys.argv)
SOURCES = verified_sources(ROOT)
ART = ROOT / "Art/Milo"
EXPORT = ART / "Export"
WORKING = ART / "Working"
RESOURCES = ROOT / "LangLearn/Resources"
for directory in (EXPORT / "preview", WORKING, RESOURCES):
    directory.mkdir(parents=True, exist_ok=True)

FPS = 30
RUNTIME_BONES = [
    ("root", None, None),
    ("hips", "root", "DEF-Hips"),
    ("spine", "hips", "DEF-Spine"),
    ("chest", "spine", "DEF-Chest"),
    ("neck", "chest", "DEF-Neck"),
    ("head", "neck", "DEF-Head"),
    ("jaw", "head", "Jaw"),
    ("eye_L", "head", "DEF-Eye.L"),
    ("eye_R", "head", "DEF-Eye.R"),
    ("clavicle_L", "chest", "DEF-Shoulder.L"),
    ("upper_arm_L", "clavicle_L", "DEF-UpperArm_1.L"),
    ("upper_arm_twist_L", "upper_arm_L", "DEF-UpperArm_2.L"),
    ("forearm_L", "upper_arm_twist_L", "DEF-Forearm_1.L"),
    ("forearm_twist_L", "forearm_L", "DEF-Forearm_2.L"),
    ("hand_L", "forearm_twist_L", "DEF-Wrist.L"),
    ("clavicle_R", "chest", "DEF-Shoulder.R"),
    ("upper_arm_R", "clavicle_R", "DEF-UpperArm_1.R"),
    ("upper_arm_twist_R", "upper_arm_R", "DEF-UpperArm_2.R"),
    ("forearm_R", "upper_arm_twist_R", "DEF-Forearm_1.R"),
    ("forearm_twist_R", "forearm_R", "DEF-Forearm_2.R"),
    ("hand_R", "forearm_twist_R", "DEF-Wrist.R"),
    ("upper_leg_L", "hips", "DEF-Thigh_1.L"),
    ("upper_leg_twist_L", "upper_leg_L", "DEF-Thigh_2.L"),
    ("lower_leg_L", "upper_leg_twist_L", "DEF-Knee_1.L"),
    ("lower_leg_twist_L", "lower_leg_L", "DEF-Knee_2.L"),
    ("foot_L", "lower_leg_twist_L", "DEF-Foot.L"),
    ("toe_L", "foot_L", "DEF-Toes.L"),
    ("upper_leg_R", "hips", "DEF-Thigh_1.R"),
    ("upper_leg_twist_R", "upper_leg_R", "DEF-Thigh_2.R"),
    ("lower_leg_R", "upper_leg_twist_R", "DEF-Knee_1.R"),
    ("lower_leg_twist_R", "lower_leg_R", "DEF-Knee_2.R"),
    ("foot_R", "lower_leg_twist_R", "DEF-Foot.R"),
    ("toe_R", "foot_R", "DEF-Toes.R"),
]
JOINT_NAMES = [entry[0] for entry in RUNTIME_BONES]
RUNTIME_SOURCE = {name: source for name, _, source in RUNTIME_BONES if source}
PARENT = {name: parent for name, parent, _ in RUNTIME_BONES}
SOURCE_POSE_BASE: dict[str, Matrix] = {}
SOURCE_SHAPE_BASE: dict[str, float] = {}


def capture_source_face(rig: bpy.types.Object, head: bpy.types.Object) -> None:
    SOURCE_POSE_BASE.clear()
    SOURCE_POSE_BASE.update({bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones})
    SOURCE_SHAPE_BASE.clear()
    if head.data.shape_keys:
        SOURCE_SHAPE_BASE.update({key.name: key.value for key in head.data.shape_keys.key_blocks})


def reset_source_face(rig: bpy.types.Object, head: bpy.types.Object) -> None:
    if rig.animation_data:
        rig.animation_data.action = None
    for pose_bone in rig.pose.bones:
        if pose_bone.name in SOURCE_POSE_BASE:
            pose_bone.matrix_basis = SOURCE_POSE_BASE[pose_bone.name]
        else:
            pose_bone.matrix_basis.identity()
    if head.data.shape_keys:
        for key in head.data.shape_keys.key_blocks:
            key.value = SOURCE_SHAPE_BASE.get(key.name, 0)
        if head.data.shape_keys.animation_data:
            for driver in head.data.shape_keys.animation_data.drivers:
                driver.mute = True
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def evaluated_copy(source: bpy.types.Object, name: str) -> bpy.types.Object:
    duplicate = source.copy()
    duplicate.data = source.data.copy()
    duplicate.name = name
    bpy.context.collection.objects.link(duplicate)
    duplicate.hide_viewport = False
    duplicate.hide_render = False
    duplicate.hide_set(False)
    for modifier in duplicate.modifiers:
        modifier.show_viewport = modifier.show_render and modifier.type != "ARMATURE"
        if modifier.type == "SUBSURF":
            modifier.levels = 0
            modifier.render_levels = 0
    if duplicate.data.shape_keys:
        duplicate.shape_key_clear()
    bpy.ops.object.select_all(action="DESELECT")
    duplicate.select_set(True)
    bpy.context.view_layer.objects.active = duplicate
    bpy.ops.object.convert(target="MESH")
    return duplicate


def weight_target(group_name: str, object_name: str) -> str:
    side = "_L" if group_name.endswith(".L") else "_R" if group_name.endswith(".R") else ""
    low = group_name.lower()
    # Exact deform-bone mappings take precedence over facial name heuristics:
    # "Forearm" contains "ear", but must never be weighted to the head.
    if group_name in RUNTIME_SOURCE.values():
        return next(name for name, source in RUNTIME_SOURCE.items() if source == group_name)
    if "eye." in low or "eye_" in low:
        return "eye" + side if side else "head"
    if any(token in low for token in ("jaw", "chin", "lip_bot", "outerlip_bot")):
        return "jaw"
    if low.startswith("def-ear") or any(token in low for token in ("head", "eyelid", "eyebrow", "cheek", "forehead", "nose", "temple", "lip")):
        return "head"
    if "neck" in low:
        return "neck"
    if "shoulder" in low:
        return "clavicle" + side
    if "upperarm_2" in low:
        return "upper_arm_twist" + side
    if "upperarm" in low:
        return "upper_arm" + side
    if "forearm_2" in low:
        return "forearm_twist" + side
    if "forearm" in low:
        return "forearm" + side
    if any(token in low for token in ("wrist", "hand", "finger", "thumb")):
        return "hand" + side
    if "thigh2" in low:
        return "upper_leg_twist" + side
    if "thigh" in low:
        return "upper_leg" + side
    if "knee2" in low:
        return "lower_leg_twist" + side
    if "knee" in low:
        return "lower_leg" + side
    if "toe" in low:
        return "toe" + side
    if "foot" in low:
        return "foot" + side
    if "hip" in low or "pelvis" in low:
        return "hips"
    if "spine" in low:
        return "spine"
    if "chest" in low or "ribcage" in low:
        return "chest"
    object_low = object_name.lower()
    if any(token in object_low for token in ("head", "hair", "eyebrow")):
        return "head"
    if any(token in object_low for token in ("eye", "cornea")):
        return "eye_L"
    if any(token in object_low for token in ("teeth_lower", "gums_lower", "tongue")):
        return "jaw"
    return "hips"


def collapse_weights(obj: bpy.types.Object) -> None:
    old_names = {group.index: group.name for group in obj.vertex_groups}
    weights: list[dict[str, float]] = []
    for vertex in obj.data.vertices:
        summed: dict[str, float] = {}
        for link in vertex.groups:
            source_group = old_names.get(link.group, "")
            if not source_group.startswith("DEF-"):
                continue
            target = weight_target(source_group, obj.name)
            if target in JOINT_NAMES:
                summed[target] = summed.get(target, 0) + link.weight
        if not summed:
            summed[weight_target("", obj.name)] = 1
        total = sum(summed.values())
        weights.append({name: value / total for name, value in summed.items()})
    obj.vertex_groups.clear()
    groups = {name: obj.vertex_groups.new(name=name) for name in JOINT_NAMES}
    for index, vertex_weights in enumerate(weights):
        retained = sorted(vertex_weights.items(), key=lambda item: item[1], reverse=True)[:4]
        retained_total = sum(weight for _, weight in retained)
        for name, weight in retained:
            groups[name].add([index], weight / retained_total, "REPLACE")


def join(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    return result


def make_runtime_rig(source_rig: bpy.types.Object) -> bpy.types.Object:
    data = bpy.data.armatures.new("MiloSkeleton_Quality")
    rig = bpy.data.objects.new("MiloRig", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, source_name in RUNTIME_BONES:
        bone = data.edit_bones.new(name)
        if source_name:
            if source_name not in source_rig.data.bones:
                raise RuntimeError(f"Missing Snow bind bone: {source_name}")
            source_bone = source_rig.data.bones[source_name]
            # A new edit bone has zero length. Establish length first so setting
            # its matrix can preserve the source orientation (including roll).
            bone.tail = Vector((0, max(source_bone.length, 0.001), 0))
            bone.matrix = source_bone.matrix_local
        else:
            bone.head = Vector((0, 0, 0))
            bone.tail = Vector((0, 0, 0.1))
        if parent:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for name, _, source_name in RUNTIME_BONES:
        if source_name:
            actual = rig.data.bones[name].matrix_local
            expected = source_rig.data.bones[source_name].matrix_local
            if max(abs(actual[row][col] - expected[row][col]) for row in range(4) for col in range(4)) > 0.0001:
                raise RuntimeError(f"Bind transform changed for {name}")
    return rig


MATERIAL_COLORS = {
    "body": (0.58, 0.31, 0.19, 1),
    "head": (0.58, 0.31, 0.19, 1),
    "shirt": (0.12, 0.105, 0.10, 1),
    "pants": (0.22, 0.26, 0.33, 1),
    "shoes": (0.10, 0.28, 0.32, 1),
    "teeth": (0.78, 0.72, 0.65, 1),
    "gums": (0.22, 0.025, 0.03, 1),
    "tongue": (0.28, 0.045, 0.06, 1),
    "eyes": (0.94, 0.96, 0.98, 1),
    "eye_dots": (0.07, 0.035, 0.02, 1),
    "hair": (0.006, 0.003, 0.002, 1),
    "eyebrows": (0.006, 0.003, 0.002, 1),
}
MATERIAL_CACHE: dict[str, bpy.types.Material] = {}
RUNTIME_TEXTURES: dict[str, str] = {}
TEXTURE_SOURCE = {
    "body": "skin_diffuse.1002.png",
    "head": "skin_diffuse.1001.png",
    "eyes": "eyes_diffuse.png",
    "shirt": "shirt_diffuse.png",
    "pants": "pants_diffuse.png",
    "shoes": "shoes_diffuse.png",
}


def bake_head_color(obj: bpy.types.Object) -> None:
    """Bake authored skin/lip node graphs to an unlit, portable base-color map."""
    obj.data.uv_layers.active_index = obj.data.uv_layers.find("UVMap")
    obj.data.uv_layers["UVMap"].active_render = True
    def emission_tree(tree):
        for node in list(tree.nodes):
            if node.type == "GROUP" and node.node_tree:
                node.node_tree = node.node_tree.copy()
                emission_tree(node.node_tree)
            elif node.type == "BSDF_PRINCIPLED":
                emission = tree.nodes.new("ShaderNodeEmission")
                color = node.inputs["Base Color"]
                emission.inputs["Color"].default_value = color.default_value
                if color.is_linked:
                    tree.links.new(color.links[0].from_socket, emission.inputs["Color"])
                for link in list(node.outputs["BSDF"].links):
                    tree.links.new(emission.outputs[0], link.to_socket)

    image = bpy.data.images.new("Milo_head_base", width=2048, height=2048, alpha=False)
    image.colorspace_settings.name = "sRGB"
    for slot in obj.material_slots:
        material = slot.material.copy()
        slot.material = material
        emission_tree(material.node_tree)
        target = material.node_tree.nodes.new("ShaderNodeTexImage")
        target.image = image
        material.node_tree.nodes.active = target
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.margin = 16
    bpy.ops.object.bake(type="EMIT")
    texture_path = EXPORT / "textures" / "head_base.png"
    texture_path.parent.mkdir(parents=True, exist_ok=True)
    image.filepath_raw = str(texture_path)
    image.file_format = "PNG"
    image.save()
    RUNTIME_TEXTURES["head"] = texture_path.name
    material = bpy.data.materials.new("Milo_head_PBR")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.58
    uv = material.node_tree.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    material.node_tree.links.new(uv.outputs["UV"], texture.inputs["Vector"])
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    # Clear object-linked overrides as well as the mesh slots.
    for slot in obj.material_slots:
        slot.link = "DATA"
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def assign_runtime_material(obj: bpy.types.Object, source_name: str) -> None:
    if source_name == "GEO-snow-head":
        bake_head_color(obj)
        return
    if source_name in (
        "GEO-snow-hair_base", "GEO-snow-eyebrows",
    ):
        # Preserve Snow's hair materials; eyes get a portable diffuse material.
        return
    render_uv_name = ""
    for index, uv_layer in enumerate(obj.data.uv_layers):
        if uv_layer.active_render:
            obj.data.uv_layers.active_index = index
            render_uv_name = uv_layer.name
            break
    key = next((token for token in MATERIAL_COLORS if token in source_name.lower()), "body")
    if key not in MATERIAL_CACHE:
        material = bpy.data.materials.new("Milo_" + key + "_PBR")
        material.diffuse_color = MATERIAL_COLORS[key]
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = MATERIAL_COLORS[key]
        shader.inputs["Roughness"].default_value = 0.58
        if key == "eyes":
            shader.inputs["Coat Weight"].default_value = 0.1
            shader.inputs["Roughness"].default_value = 0.38
        if source_filename := TEXTURE_SOURCE.get(key):
            source_path = SOURCES["snow"].parent / "textures" / source_filename
            if key == "body":
                # Snow's hands use tile 1003; wrapping every UV onto tile 1002
                # samples empty/dark texels. Flatten all three UDIMs to one atlas.
                import numpy as np
                tiles = []
                for tile in (1001, 1002, 1003):
                    part = bpy.data.images.load(str(source_path.with_name(f"skin_diffuse.{tile}.png")), check_existing=False)
                    part.scale(1024, 1024)
                    pixels = np.empty(1024 * 1024 * 4, dtype=np.float32)
                    part.pixels.foreach_get(pixels)
                    tiles.append(pixels.reshape(1024, 1024, 4))
                image = bpy.data.images.new("Milo_body_atlas", width=3072, height=1024)
                image.pixels.foreach_set(np.concatenate(tiles, axis=1).ravel())
                for uv in obj.data.uv_layers["UVMap"].data:
                    uv.uv.x /= 3
                render_uv_name = "UVMap"
            else:
                image = bpy.data.images.load(str(source_path), check_existing=False)
                image.scale(1024, 1024)
            texture_path = EXPORT / "textures" / f"{key}_base.png"
            texture_path.parent.mkdir(parents=True, exist_ok=True)
            image.filepath_raw = str(texture_path)
            image.file_format = "PNG"
            image.save()
            RUNTIME_TEXTURES[key] = texture_path.name
        else:
            image = None
        if image:
            uv_map = material.node_tree.nodes.new("ShaderNodeUVMap")
            uv_map.uv_map = render_uv_name or "UVMap"
            texture = material.node_tree.nodes.new("ShaderNodeTexImage")
            texture.image = image
            material.node_tree.links.new(uv_map.outputs["UV"], texture.inputs["Vector"])
            tint = material.node_tree.nodes.new("ShaderNodeMixRGB")
            tint.blend_type = "MULTIPLY"
            tint.inputs[0].default_value = 1
            tint.inputs[2].default_value = MATERIAL_COLORS[key]
            material.node_tree.links.new(texture.outputs["Color"], tint.inputs[1])
            material.node_tree.links.new(tint.outputs["Color"], shader.inputs["Base Color"])
        MATERIAL_CACHE[key] = material
    obj.data.materials.clear()
    obj.data.materials.append(MATERIAL_CACHE[key])
    for polygon in obj.data.polygons:
        polygon.material_index = 0


MIXAMO = {
    "spine": "Spine",
    "chest": "Spine2",
    "neck": "Neck",
    "head": "Head",
    "clavicle_L": "LeftShoulder",
    "upper_arm_L": "LeftArm",
    "forearm_L": "LeftForeArm",
    "hand_L": "LeftHand",
    "clavicle_R": "RightShoulder",
    "upper_arm_R": "RightArm",
    "forearm_R": "RightForeArm",
    "hand_R": "RightHand",
    "upper_leg_L": "LeftUpLeg",
    "lower_leg_L": "LeftLeg",
    "foot_L": "LeftFoot",
    "toe_L": "LeftToeBase",
    "upper_leg_R": "RightUpLeg",
    "lower_leg_R": "RightLeg",
    "foot_R": "RightFoot",
    "toe_R": "RightToeBase",
}


def retarget_clip(
    path: Path, runtime_rig: bpy.types.Object, action_name=None, seconds=None, stabilize_torso=False,
) -> list[list[Quaternion]]:
    before = set(bpy.data.objects)
    mapping = MIXAMO
    if path.suffix == ".gltf":
        bpy.ops.import_scene.gltf(filepath=str(path))
        mapping = {"hips": "DEF-hips", "spine": "DEF-spine.001", "chest": "DEF-spine.003",
                   "neck": "DEF-neck", "head": "DEF-head"}
        for side in ("L", "R"):
            for target, source_bone in (("clavicle", "shoulder"), ("upper_arm", "upper_arm"),
                ("forearm", "forearm"), ("hand", "hand"), ("upper_leg", "thigh"),
                ("lower_leg", "shin"), ("foot", "foot"), ("toe", "toe")):
                mapping[target + "_" + side] = "DEF-" + source_bone + "." + side
    else:
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True)
    imported = [obj for obj in set(bpy.data.objects) - before if obj.type == "ARMATURE"]
    if not imported:
        raise RuntimeError(f"No armature in {path}")
    source = imported[0]
    if action_name:
        source.animation_data.action = bpy.data.actions[action_name]
        source.animation_data.action_slot = source.animation_data.action.slots[0]
        for track in source.animation_data.nla_tracks:
            track.mute = True
    action = source.animation_data.action
    start, end = action.frame_range
    source_fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
    if seconds:
        start, end = start + seconds[0] * source_fps, start + seconds[1] * source_fps
    frame_count = max(2, round((end - start) / source_fps * FPS) + 1)
    source_names = {bone.name.split(":")[-1].removeprefix("Character1_"): bone.name for bone in source.data.bones}
    target_rest_world = {
        name: runtime_rig.matrix_world @ runtime_rig.data.bones[name].matrix_local
        for name in JOINT_NAMES
    }
    samples: list[list[Quaternion]] = []
    for sample in range(frame_count):
        frame = start + (end - start) * sample / max(1, frame_count - 1)
        bpy.context.scene.frame_set(math.floor(frame), subframe=frame % 1)
        bpy.context.view_layer.update()
        desired_world: dict[str, Matrix] = {"root": target_rest_world["root"]}
        for name in JOINT_NAMES[1:]:
            source_short = mapping.get(name)
            if source_short and source_short in source_names:
                source_name = source_names[source_short]
                source_rest = (source.matrix_world @ source.data.bones[source_name].matrix_local).to_quaternion()
                source_pose = (source.matrix_world @ source.pose.bones[source_name].matrix).to_quaternion()
                # Transfer the motion in world space. Snow and Mixamo have
                # different bone roll/local axes despite sharing a T bind pose.
                world_delta = source_pose @ source_rest.inverted()
                if stabilize_torso:
                    chest_name = source_names[mapping["chest"]]
                    chest_rest = (source.matrix_world @ source.data.bones[chest_name].matrix_local).to_quaternion()
                    chest_pose = (source.matrix_world @ source.pose.bones[chest_name].matrix).to_quaternion()
                    world_delta = chest_rest @ chest_pose.inverted() @ world_delta
                target_rest = target_rest_world[name]
                desired_rotation = world_delta @ target_rest.to_quaternion()
                desired_world[name] = Matrix.LocRotScale(
                    target_rest.translation, desired_rotation, Vector((1, 1, 1))
                )
            else:
                parent = PARENT[name]
                rest_local = target_rest_world[parent].inverted() @ target_rest_world[name]
                desired_world[name] = desired_world[parent] @ rest_local
        frame_quaternions: list[Quaternion] = []
        for name in JOINT_NAMES:
            parent = PARENT[name]
            rest_local = target_rest_world[name] if not parent else target_rest_world[parent].inverted() @ target_rest_world[name]
            posed_local = desired_world[name] if not parent else desired_world[parent].inverted() @ desired_world[name]
            delta = rest_local.inverted() @ posed_local
            quaternion = delta.to_quaternion().normalized()
            frame_quaternions.append(quaternion)
        samples.append(frame_quaternions)
    for obj in set(bpy.data.objects) - before:
        bpy.data.objects.remove(obj, do_unlink=True)
    return samples


def write_clips(path: Path, clips: list[tuple[str, bool, list[list[Quaternion]]]]) -> None:
    with path.open("wb") as output:
        output.write(b"MILO")
        output.write(struct.pack("<HHHH", 1, len(JOINT_NAMES), len(clips), FPS))
        for name in JOINT_NAMES:
            encoded = name.encode()
            output.write(struct.pack("<H", len(encoded)))
            output.write(encoded)
        for name, loops, frames in clips:
            encoded = name.encode()
            output.write(struct.pack("<H", len(encoded)))
            output.write(encoded)
            output.write(struct.pack("<HBx", len(frames), loops))
            for frame in frames:
                for quaternion in frame:
                    output.write(struct.pack("<ffff", quaternion.x, quaternion.y, quaternion.z, quaternion.w))
            for _ in frames:
                output.write(struct.pack("<fff", 0, 0, 0))


def render_portrait(
    rig: bpy.types.Object, objects: list[bpy.types.Object], filepath: Path,
    base_pose: list[Quaternion], thinking: bool, close_up: bool = False,
) -> None:
    # Each preview uses the same lighting, without accumulating earlier lights.
    for obj in list(bpy.data.objects):
        if obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = base_pose[JOINT_NAMES.index(pose_bone.name)]
    if thinking:
        rig.pose.bones["head"].rotation_mode = "XYZ"
        rig.pose.bones["head"].rotation_euler.z += 0.12
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    bounds = [obj.bound_box for obj in objects]
    center = Vector((0, 0, 1.65 if close_up else 0.95))
    bpy.ops.object.camera_add(location=(0.08, -4.8, center.z))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.72 if close_up else 2.22
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    for name, location, power, size in (
        ("Key", (-3, -4, 5), 280, 4), ("Fill", (3, -2, 3), 110, 3), ("Rim", (1, 2, 4), 180, 3)
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = power
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(filepath)
    bpy.ops.render.render(write_still=True)


def build_clips(runtime_rig):
    clips = [
        ("Idle_Neutral_A", True, retarget_clip(SOURCES["idle_neutral_a"], runtime_rig)),
        ("Idle_LookAround", True, retarget_clip(SOURCES["idle_look_around"], runtime_rig)),
        ("Idle_Chatting", True, retarget_clip(SOURCES["idle_chatting"], runtime_rig)),
        ("Idle_Watching", True, retarget_clip(SOURCES["idle_watching"], runtime_rig)),
        ("Idle_Chatting02", True, retarget_clip(SOURCES["idle_chatting_02"], runtime_rig)),
        ("Idle_LookAround02", True, retarget_clip(SOURCES["idle_look_around_02"], runtime_rig)),
        ("Walk", True, retarget_clip(SOURCES["walk_cc0"], runtime_rig, action_name="Walk_Loop")),
        ("Wave", False, retarget_clip(SOURCES["wave"], runtime_rig, seconds=(8.5, 12), stabilize_torso=True)),
        ("Laugh", False, retarget_clip(SOURCES["laugh"], runtime_rig, seconds=(3, 7))),
        ("Applaud", False, retarget_clip(SOURCES["applaud"], runtime_rig, seconds=(3, 8))),
    ]
    # These six verified recordings begin with a bind-pose calibration and
    # one interpolated sample, before the first captured pose at sample two.
    # Exclude both before making loops or using idle as a standing wave base.
    clips = [(name, loops, frames[2:] if name.startswith("Idle_") and
              all(abs(q.w) > .9999 for q in frames[0]) else frames)
             for name, loops, frames in clips]
    # The waving take was seated; retain standing legs and torso from the idle.
    idle = clips[3][2][0]
    for frame in clips[7][2]:
        for index, name in enumerate(JOINT_NAMES):
            if not (name.endswith("_L") and any(token in name for token in ("clavicle", "upper_arm", "forearm", "hand"))):
                frame[index] = idle[index].copy()
    # Blend the tail into the first pose to avoid a jump when an idle repeats.
    for name, loops, frames in clips:
        if loops and name != "Walk":
            blend_frames = min(round(FPS * 0.4), len(frames) - 1)
            for offset in range(blend_frames + 1):
                index = len(frames) - 1 - blend_frames + offset
                t = offset / blend_frames
                amount = t * t * (3 - 2 * t)
                frames[index] = [q.slerp(first, amount) for q, first in zip(frames[index], frames[0])]
    write_clips(EXPORT / "MiloClips.bin", clips)
    shutil.copy2(EXPORT / "MiloClips.bin", RESOURCES / "MiloClips.bin")

    return clips


def rebuild_clips_only():
    """Reuse the verified rig without rebaking or modifying artist assets."""
    bpy.ops.wm.open_mainfile(filepath=str(WORKING / "Milo_Generated.blend"))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE" and "upper_arm_L" in obj.data.bones)
    objects = [bpy.data.objects[name] for name in ("Milo_Head", "Milo_Eyes", "Milo_Hair", "Milo_Body")]
    clips = build_clips(rig)
    manifest_path = EXPORT / "rig-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["clips"] = [{"name": name, "frames": len(frames), "fps": FPS, "loops": loops} for name, loops, frames in clips]
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copy2(manifest_path, RESOURCES / "MiloRigManifest.json")
    (EXPORT / "clips.json").write_text(json.dumps({"debugOnly": True, "clips": manifest["clips"]}, indent=2) + "\n")
    for name, _, frames in clips[-2:]:
        render_portrait(rig, objects, EXPORT / "preview" / f"{name}.png", frames[len(frames) // 2], False)


def main() -> None:
    shutil.rmtree(EXPORT / "textures", ignore_errors=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCES["snow"]))
    source_rig = bpy.data.objects["RIG-Snow"]
    source_head = bpy.data.objects["GEO-snow-head"]
    capture_source_face(source_rig, source_head)
    reset_source_face(source_rig, source_head)
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            for modifier in obj.modifiers:
                if modifier.type == "SUBSURF":
                    modifier.levels = modifier.render_levels = 0

    runtime_rig = make_runtime_rig(source_rig)
    face_copies, blend_shapes = bake_face(source_rig)
    export_names = {
        "Milo_Head": ["GEO-snow-head", "GEO-snow-teeth_upper", "GEO-snow-teeth_lower",
                      "GEO-snow-gums_upper", "GEO-snow-gums_lower", "GEO-snow-tongue", "GEO-snow-eyebrows"],
        "Milo_Eyes": ["GEO-snow-eyes"],
        "Milo_Hair": ["GEO-snow-hair_base"],
        "Milo_Body": [
            "GEO-snow-body", "GEO-snow-pants", "GEO-snow-shirt", "GEO-snow-shoes_base",
            "GEO-snow-shoes_bottom", "GEO-snow-shoes_parts",
        ],
    }
    runtime_objects: list[bpy.types.Object] = []
    for output_name, names in export_names.items():
        copies = [
            face_copies[name]
            if name in face_copies
            else evaluated_copy(bpy.data.objects[name], name + "_runtime")
            for name in names
        ]
        for copy, source_name in zip(copies, names):
            if source_name not in face_copies:
                collapse_weights(copy)
            assign_runtime_material(copy, source_name)
        runtime_objects.append(join(copies, output_name))
    runtime_head = next(obj for obj in runtime_objects if obj.name == "Milo_Head")
    for obj in runtime_objects:
        obj.parent = runtime_rig
        modifier = obj.modifiers.new("Milo skin", "ARMATURE")
        modifier.object = runtime_rig

    source_collection_names = {obj.name for obj in runtime_objects} | {runtime_rig.name}
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj.name not in source_collection_names
        obj.hide_viewport = obj.name not in source_collection_names

    generated = safe_output(ROOT, "Art/Milo/Working/Milo_Generated.blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(generated))
    master = WORKING / "Milo_Master.blend"
    if not master.exists():
        shutil.copy2(generated, master)

    clips = build_clips(runtime_rig)

    bpy.ops.object.select_all(action="DESELECT")
    runtime_rig.select_set(True)
    for obj in runtime_objects:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = runtime_rig
    usdz = EXPORT / "Milo.usdz"
    bpy.ops.wm.usd_export(
        filepath=str(usdz), selected_objects_only=True, export_animation=False,
        export_armatures=True, export_shapekeys=True, export_materials=True,
        export_normals=True, generate_preview_surface=True,
    )
    shutil.copy2(usdz, RESOURCES / "Milo.usdz")

    triangles = 0
    vertices = 0
    for obj in runtime_objects:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
        vertices += len(obj.data.vertices)
    manifest = {
        "model": "Milo", "version": 2,
        "source": "Snow v4.2 (Blender Studio, CC-BY-4.0)",
        "rigVariant": "quality", "vertices": vertices, "triangles": triangles,
        "joints": JOINT_NAMES, "jointCount": len(JOINT_NAMES),
        "meshes": [obj.name for obj in runtime_objects],
        "materials": sorted({slot.material.name for obj in runtime_objects for slot in obj.material_slots if slot.material}),
        "textures": sorted(set(RUNTIME_TEXTURES.values())), "blendShapes": blend_shapes,
        "clips": [{"name": name, "frames": len(frames), "fps": FPS, "loops": loops} for name, loops, frames in clips],
    }
    (EXPORT / "rig-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copy2(EXPORT / "rig-manifest.json", RESOURCES / "MiloRigManifest.json")
    (EXPORT / "clips.json").write_text(json.dumps({"debugOnly": True, "clips": manifest["clips"]}, indent=2) + "\n")

    portrait_pose = clips[0][2][len(clips[0][2]) // 2]
    render_portrait(runtime_rig, runtime_objects, ROOT / "LangLearn/Assets.xcassets/Milo.imageset/milo.png", portrait_pose, False, True)
    render_portrait(runtime_rig, runtime_objects, ROOT / "LangLearn/Assets.xcassets/MiloThinking.imageset/milo-thinking.png", portrait_pose, True, True)
    identity_pose = [Quaternion() for _ in JOINT_NAMES]
    render_portrait(runtime_rig, runtime_objects, EXPORT / "preview/Rest_Pose.png", identity_pose, False)
    render_portrait(runtime_rig, runtime_objects, EXPORT / "preview/Face_CloseUp.png", identity_pose, False, True)
    for name, _, frames in clips:
        render_portrait(runtime_rig, runtime_objects, EXPORT / "preview" / f"{name}.png", frames[len(frames) // 2], False)
    for name, values in [("Open", {"mouthOpen": 1}), ("Blink", {"blinkL": 1, "blinkR": 1}), ("Smile", {"smileL": 1, "smileR": 1})]:
        for key in runtime_head.data.shape_keys.key_blocks:
            key.value = values.get(key.name, 0)
        render_portrait(runtime_rig, runtime_objects, EXPORT / "preview" / f"Face_{name}.png", identity_pose, False, True)
    print("MILO_MANIFEST", json.dumps(manifest))


if __name__ == "__main__":
    if "--clips-only" in sys.argv:
        rebuild_clips_only()
    else:
        main()
