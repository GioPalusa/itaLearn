"""Bake Snow's evaluated face rig to independent, neutral-relative morphs."""
import bpy

FACE_OBJECTS = ["GEO-snow-head", "GEO-snow-eyebrows", "GEO-snow-teeth_upper",
                "GEO-snow-teeth_lower", "GEO-snow-gums_upper", "GEO-snow-gums_lower", "GEO-snow-tongue"]


def bake_face(rig):
    objects = [bpy.data.objects[name] for name in FACE_OBJECTS]
    bases = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
    for obj in objects:
        for modifier in obj.modifiers:
            if modifier.type == "SUBSURF":
                modifier.levels = modifier.render_levels = 0
        if obj.data.shape_keys and obj.data.shape_keys.animation_data:
            for driver in obj.data.shape_keys.animation_data.drivers:
                driver.mute = False

    def reset():
        rig.animation_data.action = None
        for bone in rig.pose.bones:
            bone.matrix_basis = bases[bone.name]
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()

    def pose(action=None, jaw=0):
        reset()
        if action:
            animation = bpy.data.actions[action]
            rig.animation_data.action = animation
            rig.animation_data.action_slot = animation.slots[0]
            bpy.context.scene.frame_set(round(animation.frame_range[1]))
        if jaw:
            rig.pose.bones["Jaw"].rotation_mode = "XYZ"
            rig.pose.bones["Jaw"].rotation_euler.x = jaw
        bpy.context.view_layer.update()

    def positions(obj):
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        result = [vertex.co.copy() for vertex in mesh.vertices]
        evaluated.to_mesh_clear()
        return result

    reset()
    copies = {}
    neutral = {}
    for source in objects:
        evaluated = source.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True,
                                             depsgraph=bpy.context.evaluated_depsgraph_get())
        obj = bpy.data.objects.new(source.name + "_runtime", mesh)
        bpy.context.collection.objects.link(obj)
        # new_from_object retains polygon assignments; copy object-linked overrides.
        obj.data.materials.clear()
        for slot in source.material_slots:
            obj.data.materials.append(slot.material)
        for group in source.vertex_groups:
            obj.vertex_groups.new(name=group.name)
        # The face mesh includes the neck and upper chest. Preserve those skin
        # influences so head turns cannot pull the neckline out of the shirt.
        body_groups = {"DEF-Neck": "neck", "DEF-Chest": "chest",
                       "DEF-Shoulder.L": "clavicle_L", "DEF-Shoulder.R": "clavicle_R"}
        weights = []
        for vertex in mesh.vertices:
            summed = {}
            for link in vertex.groups:
                name = obj.vertex_groups[link.group].name
                bone = rig.data.bones.get(name)
                if not bone or not bone.use_deform:
                    continue
                target = body_groups.get(name, "head")
                summed[target] = summed.get(target, 0) + link.weight
            total = sum(summed.values())
            weights.append({name: value / total for name, value in summed.items()} if total else {"head": 1})
        obj.vertex_groups.clear()
        groups = {name: obj.vertex_groups.new(name=name) for name in ["head", "neck", "chest", "clavicle_L", "clavicle_R"]}
        for index, values in enumerate(weights):
            for name, value in values.items():
                groups[name].add([index], value, "REPLACE")
        obj.shape_key_add(name="Basis")
        neutral[source.name] = [v.co.copy() for v in mesh.vertices]
        copies[source.name] = obj

    recipes = {
        "mouthOpen": (None, .48, None),
        "blinkL": ("Eyemask Closed", 0, "L"), "blinkR": ("Eyemask Closed", 0, "R"),
        "smileL": ("Mouth Teethsmile", 0, "L"), "smileR": ("Mouth Teethsmile", 0, "R"),
        "mouthWide": ("Mouth Teethsmile", 0, None),
        "mouthNarrow": ("Mouth Narrow", 0, None),
        "mouthPucker": ("Mouth Uu", 0, None), "mouthFV": ("Mouth Ff", 0, None),
        "browRaiseL": ("Eyemask Scared", 0, "L"), "browRaiseR": ("Eyemask Scared", 0, "R"),
        "browDownL": ("Eyemask Angry", 0, "L"), "browDownR": ("Eyemask Angry", 0, "R"),
        "cheekRaiseL": ("Mouth Teethsmile", 0, "L"), "cheekRaiseR": ("Mouth Teethsmile", 0, "R"),
    }
    for name, (action, jaw, side) in recipes.items():
        pose(action, jaw)
        for source in objects:
            obj = copies[source.name]
            base = neutral[source.name]
            coords = positions(source)
            if len(coords) != len(base):
                raise RuntimeError(f"Face topology changed: {source.name}/{name}")
            key = obj.shape_key_add(name=name)
            key.value = 0
            for index, (target, origin) in enumerate(zip(coords, base)):
                amount = 1 if side is None else min(1, max(0, origin.x * (1 if side == "L" else -1) / .012))
                key.data[index].co = origin + (target - origin) * amount
        head = copies["GEO-snow-head"]
        delta = max((p.co - b.co).length for p, b in zip(head.data.shape_keys.key_blocks[name].data, head.data.shape_keys.key_blocks[0].data))
        if delta < .001:
            raise RuntimeError(f"Empty facial motion: {name} ({delta})")
    reset()
    return copies, list(recipes)
