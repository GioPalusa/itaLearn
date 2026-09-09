"""Blender regression checks. Run with the same environment/arguments as build_all.py."""
import unittest
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).parent))
import build_all as milo


class ArmRigTests(unittest.TestCase):
    def test_head_has_baked_color_on_render_uv(self):
        bpy.ops.wm.open_mainfile(filepath=str(milo.WORKING / "Milo_Generated.blend"))
        head = bpy.data.objects["Milo_Head"]
        self.assertEqual(head.data.uv_layers.active.name, "UVMap")
        material = head.material_slots[0].material
        shader = material.node_tree.nodes.get("Principled BSDF")
        texture = shader.inputs["Base Color"].links[0].from_node
        self.assertEqual(texture.type, "TEX_IMAGE")
        image = texture.image
        colored = 0
        samples = 0
        for y in range(32, image.size[1], 64):
            for x in range(32, image.size[0], 64):
                index = (y * image.size[0] + x) * 4
                r, g, b = image.pixels[index:index + 3]
                colored += r > g * 1.1 and g > b * 1.1 and r > 0.02
                samples += 1
        self.assertGreater(colored / samples, 0.35, "Missing skin color or wrong bake UV map")

    def test_arm_weights_never_resolve_to_face_or_clavicle(self):
        for side in ("L", "R"):
            for source, target in (
                ("UpperArm_1", "upper_arm"),
                ("UpperArm_2", "upper_arm_twist"),
                ("Forearm_1", "forearm"),
                ("Forearm_2", "forearm_twist"),
                ("Wrist", "hand"),
                ("Finger_Index1", "hand"),
            ):
                self.assertEqual(milo.weight_target(f"DEF-{source}.{side}", "GEO-snow-body"), f"{target}_{side}")
            self.assertEqual(milo.weight_target(f"DEF-Ear2.{side}", "GEO-snow-head"), "head")

    def test_imported_bind_axes_and_lengths_match_snow(self):
        bpy.ops.wm.open_mainfile(filepath=str(milo.SOURCES["snow"]))
        source = bpy.data.objects["RIG-Snow"]
        runtime = milo.make_runtime_rig(source)
        for name, _, source_name in milo.RUNTIME_BONES:
            if source_name:
                actual = runtime.data.bones[name]
                expected = source.data.bones[source_name]
                self.assertLess((actual.head_local - expected.head_local).length, 0.0001, name)
                self.assertLess((actual.tail_local - expected.tail_local).length, 0.0001, name)

    def test_exported_forearm_surface_tracks_arm(self):
        bpy.ops.wm.open_mainfile(filepath=str(milo.WORKING / "Milo_Generated.blend"))
        body = bpy.data.objects["Milo_Body"]
        for side, sign in (("L", 1), ("R", -1)):
            # A central forearm vertex must follow the arm, never the head.
            vertex = min(body.data.vertices, key=lambda v: (v.co.x - sign * 0.55) ** 2 + (v.co.z - 1.34) ** 2 + v.co.y ** 2)
            weights = {body.vertex_groups[item.group].name: item.weight for item in vertex.groups}
            self.assertNotIn("head", weights)
            self.assertGreater(sum(weight for name, weight in weights.items() if name in (f"forearm_{side}", f"forearm_twist_{side}")), 0.95)
            self.assertAlmostEqual(sum(weights.values()), 1, places=5)


result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ArmRigTests))
if not result.wasSuccessful():
    raise RuntimeError("Milo arm regression checks failed")
