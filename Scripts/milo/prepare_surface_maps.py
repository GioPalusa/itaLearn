"""Prepare Snow's supplied CC-BY surface maps without modifying the rig.
blender -b --python Scripts/milo/prepare_surface_maps.py -- /path/to/snow_barscene_pack
"""
from pathlib import Path
import sys, json, hashlib
import bpy
import numpy as np
root = Path(__file__).resolve().parents[2]
source = Path(sys.argv[sys.argv.index('--') + 1]) / 'lib/snow/maps/bake'
out = root / 'LangLearn/Resources'
records = []

def read(name, color=False):
    path = source / name
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    image.scale(1024, 1024)
    pixels = np.empty(1024 * 1024 * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    records.append({'source': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    bpy.data.images.remove(image)
    return pixels.reshape(1024, 1024, 4)

def save(name, pixels, color=False):
    height, width, _ = pixels.shape
    image = bpy.data.images.new(name, width=width, height=height)
    image.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(out / ('MiloSurface_' + name + '.png'))
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)

for kind in ('roughness', 'sss_color', 'sss_value'):
    color = kind == 'sss_color'
    tiles = [read(f'skin_{kind}.{tile}.png', color) for tile in (1001,1002,1003)]
    save('head_' + kind, tiles[0], color)
    save('body_' + kind, np.concatenate(tiles, axis=1), color)
for part in ('hair', 'shirt', 'pants', 'shoes'):
    save(part + '_roughness', read(part + '_roughness.png'))
for part in ('shirt', 'pants', 'shoes'):
    save(part + '_normal', read(part + '_normal.png'))
(root / 'Art/Milo/surface-sources.json').write_text(json.dumps({'author':'Blender Studio', 'license':'CC-BY-4.0', 'pack':'snow_barscene_pack', 'modifications':'Resized to 1024 per tile; body UDIMs flattened to match existing UV atlas.', 'files':records}, indent=2) + '\n')

# A small, authored studio environment: broad warm key and subdued cool fill.
# This contains lighting only, not imagery from the supplied bar-scene background.
h, w = 256, 512
y, x = np.mgrid[0:h, 0:w]
u, v = x / w, y / h
key = np.exp(-(((u-.35)/.13)**2 + ((v-.68)/.20)**2))
fill = np.exp(-(((u-.72)/.21)**2 + ((v-.58)/.30)**2))
pixels = np.ones((h,w,4), dtype=np.float32)
for c, (warm,cool) in enumerate(zip((.85,.78,.68),(.19,.22,.27))):
    pixels[:,:,c] = .055 + warm*key + cool*fill
save('studio', pixels, color=True)
