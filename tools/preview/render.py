"""Draws filmstrips of the frames pose.luau wrote: front, side and top views of an R15 rig with the ball.
Run from the repo root: python3 tools/preview/render.py [AnimationName ...]   (needs matplotlib)
Right-side limbs are red, left-side limbs green; the faint dots are the ball's whole path."""
import json, sys, glob, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Circle

OUT = "tools/preview/out"
COLORS = {"Torso": "#5b7bd5", "Head": "#e8c547", "Right": "#d9534f", "Left": "#4caf50", "HumanoidRootPart": None}
FLOOR_Y = 1  # Hoops.FLOOR_Y
BALL_R = 0.6
LIGHT = (0.4, 0.8, -0.45)

# view name -> (screen-right axis, screen-up axis, toward-camera axis); character faces -Z
VIEWS = {
    "front": ((-1, 0, 0), (0, 1, 0), (0, 0, -1)),
    "side": ((0, 0, -1), (0, 1, 0), (1, 0, 0)),
    "top": ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
}

def dot(a, b):
    return sum(x * y for x, y in zip(a, b))

def color(name):
    for key in ("Right", "Left", "Head"):
        if name.startswith(key):
            return COLORS[key]
    return COLORS["Torso"] if "Torso" in name else None

def faces(part):
    x, y, z, *r = part["cf"]
    rx, ry, rz = (r[0], r[3], r[6]), (r[1], r[4], r[7]), (r[2], r[5], r[8])  # rotation columns
    sx, sy, sz = (s / 2 for s in part["size"])
    def corner(a, b, c):
        return tuple(p + a * sx * u + b * sy * v + c * sz * w for p, u, v, w in zip((x, y, z), rx, ry, rz))
    for axis, (u, v, w) in enumerate(((rx, ry, rz), (ry, rz, rx), (rz, rx, ry))):
        for sign in (1, -1):
            if axis == 0:
                pts = [corner(sign, a, b) for a, b in ((1, 1), (1, -1), (-1, -1), (-1, 1))]
            elif axis == 1:
                pts = [corner(a, sign, b) for a, b in ((1, 1), (1, -1), (-1, -1), (-1, 1))]
            else:
                pts = [corner(a, b, sign) for a, b in ((1, 1), (1, -1), (-1, -1), (-1, 1))]
            yield pts, tuple(sign * c for c in u)

def draw(ax, frame, trail, view):
    right, up, toward = VIEWS[view]
    shapes = []
    for part in frame["parts"]:
        c = color(part["name"])
        if not c:
            continue
        for pts, normal in faces(part):
            if dot(normal, toward) <= 0:
                continue  # facing away from the camera
            shade = 0.55 + 0.45 * max(0, dot(normal, LIGHT))
            depth = sum(dot(p, toward) for p in pts) / 4
            shapes.append((depth, "poly", [(dot(p, right), dot(p, up)) for p in pts], c, shade))
    if frame.get("ball"):
        b = frame["ball"]
        shapes.append((dot(b, toward) + BALL_R, "ball", (dot(b, right), dot(b, up)), "#ff8c1a", 1))
    for p in trail:
        ax.plot(dot(p, right), dot(p, up), ".", color="#ff8c1a", alpha=0.25, markersize=3)
    for depth, kind, geo, c, shade in sorted(shapes, key=lambda s: s[0]):
        if kind == "poly":
            rgb = matplotlib.colors.to_rgb(c)
            ax.add_patch(Polygon(geo, closed=True, facecolor=tuple(ch * shade for ch in rgb), edgecolor="black", linewidth=0.4))
        else:
            ax.add_patch(Circle(geo, BALL_R, facecolor=c, edgecolor="black", linewidth=0.6, zorder=10))
    if view != "top":
        ax.axhline(FLOOR_Y, color="#8b5a2b", linewidth=1.5)
        ax.set_ylim(FLOOR_Y - 0.5, FLOOR_Y + 7)
    else:
        ax.set_ylim(-3.5, 3.5)
    ax.set_xlim(-3.5, 3.5)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])

def render(path):
    data = json.load(open(path))
    frames = data["frames"]
    fig, axes = plt.subplots(3, len(frames), figsize=(2.0 * len(frames), 7.2))
    for col, frame in enumerate(frames):
        for row, view in enumerate(VIEWS):
            ax = axes[row][col]
            draw(ax, frame, data["trail"], view)
            if row == 0:
                ax.set_title(f"{frame['t']:.2f}s", fontsize=9)
            if col == 0:
                ax.set_ylabel(view, fontsize=9)
    rig = "exact rig" if data["exact"] else "guessed rig"
    fig.suptitle(f"{data['name']} ({data['length']:.2f}s, {rig}). Red = right side, green = left", fontsize=10)
    fig.tight_layout()
    out = path.replace(".json", ".png")
    fig.savefig(out, dpi=70)
    plt.close(fig)
    return out

if __name__ == "__main__":
    names = sys.argv[1:]
    paths = [f"{OUT}/{n}.json" for n in names] if names else sorted(glob.glob(f"{OUT}/*.json"))
    for p in paths:
        print(render(p))
