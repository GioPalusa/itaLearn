"""Contact-constrained applause for Snow's proportions (metres, Blender Z-up)."""
import math
from mathutils import Matrix, Quaternion, Vector


def build_applause(rig, names, source, fps):
    parents = {n: rig.data.bones[n].parent.name if rig.data.bones[n].parent else None for n in names}
    rest = {n: rig.data.bones[n].matrix_local.copy() for n in names}
    local = {n: rest[parents[n]].inverted() @ rest[n] if parents[n] else rest[n] for n in names}
    indices = {n:i for i,n in enumerate(names)}

    def fk(frame):
        matrices = {}
        for n in names:
            m = local[n] @ frame[indices[n]].to_matrix().to_4x4()
            matrices[n] = matrices[parents[n]] @ m if parents[n] else m
        return matrices

    def orient(frame, name, desired, matrices):
        parent = matrices[parents[name]].to_quaternion() if parents[name] else Quaternion()
        frame[indices[name]] = (local[name].to_quaternion().inverted() @ parent.inverted() @ desired).normalized()

    def solve(frame, side, target, orientation):
        hand = 'hand_' + side
        # Solve wrist position first, then orient the palm without moving wrist.
        for _ in range(35):
            matrices = fk(frame)
            if (matrices[hand].translation - target).length < .0002:
                break
            for joint in ('forearm_' + side, 'upper_arm_' + side):
                matrices = fk(frame)
                pivot = matrices[joint].translation
                current = matrices[hand].translation - pivot
                desired = target - pivot
                rotation = current.rotation_difference(desired)
                orient(frame, joint, rotation @ matrices[joint].to_quaternion(), matrices)
        orient(frame, hand, orientation, fk(frame))

    # Fingers point up and slightly forward. Mirrored Snow hand rolls mean
    # local +X is the left palm normal, local -X the right palm normal.
    y = Vector((0, -.18, .984)).normalized()
    x = Vector((-1, 0, 0))
    z = x.cross(y)
    orientation = Matrix((x, y, z)).transposed().to_quaternion()
    duration, lead, period, beats = 3.9, .5, .48, 6
    frames, measurements = [], []
    for index in range(round(duration*fps)+1):
        t = index/fps
        frame = [q.copy() for q in source[round(index*(len(source)-1)/(duration*fps))]]
        phase = (t-lead) % period
        if t < lead or t > lead+beats*period:
            closure = 0
        elif phase < .18:
            u = phase/.18; closure = u*u*(3-2*u)
        elif phase < .27:
            closure = 1
        else:
            u = (phase-.27)/(period-.27); closure = 1-u*u*(3-2*u)
        half_gap = .15*(1-closure) + .014*closure
        for side,sign in [('L',1),('R',-1)]:
            solve(frame, side, Vector((sign*half_gap, -.32, 1.20)), orientation)
        matrices = fk(frame)
        palms = [matrices['hand_'+side] @ Vector((sign*.012,.06,0)) for side,sign in [('L',1),('R',-1)]]
        measurements.append({'time':round(t,4),'contact':closure == 1,'gap':(palms[0]-palms[1]).length})
        frames.append(frame)
    contact_gaps = [m['gap'] for m in measurements if m['contact']]
    assert max(contact_gaps) < .006, max(contact_gaps)
    return frames, measurements
