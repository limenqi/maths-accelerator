# pixel-by-pixel renderer 
#
# object is always an axis-aligned rectangle with configurable half_width and
# source marker is a green crosshair drawn on the wave field
# object outline is grey (96, 96, 96)

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from matplotlib.animation import FuncAnimation

# simulation space
WIDTH, HEIGHT = 320, 240 
BORDER = 50 

# wave physics
C = 0.5 # wave speed in pixels per timestep
K = C * C # propaogation coefficient (stability requires K < 0.5)
frequency = [0.01] 
CYCLES = 1 # 1 complete wave 
pulse_duration= [int(CYCLES /frequency[0])] # how long the source stay on (how many timesteps is 1 cycle at the frequency

# source and object positions
source_position = [80, 120]
object_position = [200, 120]

# object is a rectangle: half_width and half_height control its size
# default 20x20 px (half=10) matches the RTL default
object_half_width  = [10]
object_half_height = [10]

# pulse parameters
gain = [0.8]

paused = [False]

pulse_fired_time = [None]

yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH] # numpy allows two 2D arrays (rows), comparing element by element across the whole row at once 

# damping 
damping = np.ones((HEIGHT, WIDTH), np.float32) # this line creates a grid where every cell starts at value 1.0 = no absorption
for i in range(BORDER): # counts from 0 to 49, each value of i represents 1 strip of cells parallel to an edge, starting from the outermost strip at the edge and moving inward 
    v = np.sin(0.5 * np.pi * (i + 1) / BORDER) ** 2 # v is the multiplier applied to the wave. at i = 0 (outermost strip), v = 0 = wave killed = full absorption. at i = BORDER - 1 (innermost strip), v = 1 = wave unchanged = no absorption as it is near the simulation interior. 
    damping[i, :] = np.minimum(damping[i, :], v) # top edge (for every cell in the top row, set to whichever is smaller, current damping value or the new v )
    damping[HEIGHT-1-i, :] = np.minimum(damping[HEIGHT-1-i, :], v) # bottom edge 
    damping[:, i] = np.minimum(damping[:, i], v) # left edge 
    damping[:, WIDTH-1-i] = np.minimum(damping[:, WIDTH-1-i], v) # right edge 


def make_object_mask(cx, cy, hw, hh):
    # axis-aligned rectangle
    x0 = max(cx - hw, 0)
    x1 = min(cx + hw, WIDTH - 1)
    y0 = max(cy - hh, 0)
    y1 = min(cy + hh, HEIGHT - 1)
    return (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)

# wave fields
previous_wave = np.zeros((HEIGHT, WIDTH), np.float32)
current_wave = np.zeros((HEIGHT, WIDTH), np.float32)
t = [0]
object_mask = make_object_mask (object_position[0], object_position[1], object_half_width[0], object_half_height[0]) # store grid region fo object

# source stencil — 3x3 Gaussian-weighted injection
source_stencil = np.array([
    [0.05, 0.10, 0.05],
    [0.10, 1.00, 0.10],
    [0.05, 0.10, 0.05],
], dtype=np.float32)

source_stencil /= source_stencil.sum() # normalisation to keep the total energy correct

DISPLAY_PRESSURE_LIMIT = 0.5
rendered_frame = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)


def render_wave_pixel_by_pixel(wave, obj_mask, frame):
    #   positive pressure -> red tint (r=255, g=255-vis, b=255-vis)
    #   negative pressure -> blue tint (r=255-vis, g=255-vis, b=255)
    #   zero -> white
    for y in range(HEIGHT):
        for x in range(WIDTH):
            pressure = wave[y, x]
            visibility = int(min(abs(pressure) / DISPLAY_PRESSURE_LIMIT * 255.0, 255.0))

            if pressure > 0:
                r, g, b = 255, 255 - visibility, 255 - visibility
            elif pressure < 0:
                r, g, b = 255 - visibility, 255 - visibility, 255
            else:
                r, g, b = 255, 255, 255

            # grey rectangle outline 
            cx = object_position[0]
            cy = object_position[1]
            hw = object_half_width[0]
            hh = object_half_height[0]
            x0 = max(cx - hw, 0); x1 = min(cx + hw, WIDTH - 1)
            y0 = max(cy - hh, 0); y1 = min(cy + hh, HEIGHT - 1)
            on_x_edge = (x == x0 or x == x1) and (y0 <= y <= y1)
            on_y_edge = (y == y0 or y == y1) and (x0 <= x <= x1)
            if on_x_edge or on_y_edge:
                r, g, b = 96, 96, 96

            # green crosshair source marker 
            sx, sy = source_position[0], source_position[1]
            dx = abs(x - sx); dy = abs(y - sy)
            if (dx == 0 and dy <= 4) or (dy == 0 and dx <= 4):
                r, g, b = 0, 200, 0

            frame[y, x, 0] = r
            frame[y, x, 1] = g
            frame[y, x, 2] = b

    return frame


# display layout
fig = plt.figure(figsize=(13, 6), facecolor='#0a0f1e')
fig.canvas.manager.set_window_title('Wave Simulation')
split_screen = gridspec.GridSpec(1, 2, width_ratios=[2.5, 1], wspace=0.3)
wave_panel = fig.add_subplot(split_screen[0])
info_panel = fig.add_subplot(split_screen[1])

for panel in [wave_panel, info_panel]:
    panel.set_facecolor('#0a0f1e')
    panel.tick_params(colors='#8899aa')
    for spine in panel.spines.values():
        spine.set_edgecolor('#223355')

wave_panel.set_title(
    'WASD=source  Arrows=object  Space=fire  G/F=gain  ]/[=duration  Scroll=resize  E=obj on/off  R=reset',
    color='#aabbcc', fontsize=8
)
wave_panel.axis('off')

render_wave_pixel_by_pixel(current_wave, object_mask, rendered_frame)
wave_image = wave_panel.imshow(rendered_frame, interpolation='nearest', aspect='equal', extent=[0, WIDTH, HEIGHT, 0])

info_panel.axis('off')
info_text = info_panel.text(0.05, 0.98,'', transform=info_panel.transAxes, va='top', fontsize=7.5, family='monospace', color='#aabbcc')

# function to update object position and redraw the object when it is moved 
def rebuild_object():
    if object_enabled[0]:
        object_mask[:] = make_object_mask(object_position[0], object_position[1], object_half_width[0], object_half_height[0])
    else:
        object_mask[:] = False


STEP = 10  # pixels per keypress, matching the UI STEP=20 at 2x scale

object_enabled = [True]


def on_click(event):
    # left click sets source position, right click sets object position
    if event.inaxes != wave_panel or event.xdata is None:
        return
    nx = int(np.clip(event.xdata, 0, WIDTH-1))
    ny = int(np.clip(event.ydata, 0, HEIGHT-1))
    if event.button == 1: # left click to set new source position 
        source_position[0], source_position[1] = nx, ny
    elif event.button == 3: # right click to set new object position 
        object_position[0], object_position[1] = nx, ny
        rebuild_object()
    fig.canvas.draw_idle()

# keyboard event handler 
def on_scroll(event):
    # scroll resizes the object 
    # shift+scroll = width only, ctrl+scroll = height only, plain = both
    delta = 1 if event.button == 'up' else -1
    if event.key == 'shift':
        object_half_width[0]  = max(1, min(object_half_width[0]  + delta, WIDTH // 2))
    elif event.key == 'control':
        object_half_height[0] = max(1, min(object_half_height[0] + delta, HEIGHT // 2))
    else:
        object_half_width[0]  = max(1, min(object_half_width[0]  + delta, WIDTH // 2))
        object_half_height[0] = max(1, min(object_half_height[0] + delta, HEIGHT // 2))
    rebuild_object()


def on_key(event):
    # WASD moves source, arrow keys move object
    if event.key == ' ':
        if pulse_fired_time[0] is None:
            pulse_fired_time[0] = t[0]
    elif event.key == 'w':
        source_position[1] = max(0, source_position[1] - STEP)
    elif event.key == 's':
        source_position[1] = min(HEIGHT - 1, source_position[1] + STEP)
    elif event.key == 'a':
        source_position[0] = max(0, source_position[0] - STEP)
    elif event.key == 'd':
        source_position[0] = min(WIDTH - 1, source_position[0] + STEP)
    elif event.key == 'up':
        object_position[1] = max(0, object_position[1] - STEP)
        rebuild_object()
    elif event.key == 'down':
        object_position[1] = min(HEIGHT - 1, object_position[1] + STEP)
        rebuild_object()
    elif event.key == 'left':
        object_position[0] = max(0, object_position[0] - STEP)
        rebuild_object()
    elif event.key == 'right':
        object_position[0] = min(WIDTH - 1, object_position[0] + STEP)
        rebuild_object()
    elif event.key == 'g':
        gain[0] = min(gain[0] + 0.1, 2.0)
    elif event.key == 'f':
        gain[0] = max(gain[0] - 0.1, 0.05)
    elif event.key == ']':
        pulse_duration[0] = min(pulse_duration[0] + int(CYCLES / frequency[0] * 0.1) + 1, 2000)
    elif event.key == '[':
        pulse_duration[0] = max(pulse_duration[0] - int(CYCLES / frequency[0] * 0.1) - 1, 1)
    elif event.key == 'e':
        object_enabled[0] = not object_enabled[0]
        rebuild_object()
    elif event.key == 'r':
        previous_wave[:] = 0
        current_wave[:]  = 0
        t[0] = 0
        pulse_fired_time[0] = None
        source_position[:] = [80, 120]
        object_position[:] = [200, 120]
        object_half_width[0]  = 10
        object_half_height[0] = 10
        object_enabled[0] = True
        gain[0] = 0.8
        rebuild_object()
    elif event.key in ('q', 'escape'):
        plt.close('all')

STEPS_PER_FRAME = 4 # runs 4 physics steps per displayed frame.

def update(_):
    # if pause pressed, skip the update and just return current display state  
    if paused[0]:
        return wave_image, info_text

    global previous_wave, current_wave

    for _ in range(STEPS_PER_FRAME):
        next_wave = np.empty_like(current_wave)
        centre    = current_wave[1:-1, 1:-1]

        # rigid BC - Neumann fake cell
        up    = np.where(object_mask[:-2,  1:-1], centre, current_wave[:-2,  1:-1])
        down  = np.where(object_mask[2:,   1:-1], centre, current_wave[2:,   1:-1])
        left  = np.where(object_mask[1:-1, :-2],  centre, current_wave[1:-1, :-2])
        right = np.where(object_mask[1:-1, 2:],   centre, current_wave[1:-1, 2:])
        laplacian = up + down + left + right - 4.0 * centre

        next_wave[1:-1, 1:-1] = 0.0
        fluid = ~object_mask[1:-1, 1:-1]
        next_wave[1:-1, 1:-1][fluid] = (
            2 * centre[fluid] - previous_wave[1:-1, 1:-1][fluid] + K * laplacian[fluid]
        )

        # Neumann edges - no reflection at grid boundary
        next_wave[0, :] = next_wave[1, :] # top row takes value from the row below
        next_wave[-1, :] = next_wave[-2, :] # bottom row takes value from the row above
        next_wave[:, 0] = next_wave[:, 1] # left column takes value from the column to the right
        next_wave[:, -1] = next_wave[:, -2] # right column takes value from the column to the left

        # apply damping to both grids
        next_wave    *= damping
        current_wave *= damping
        next_wave[object_mask]    = 0.0
        current_wave[object_mask] = 0.0

        # source injection
        if pulse_fired_time[0] is not None:
            age = t[0] - pulse_fired_time[0]
            if age < pulse_duration[0]:
                amplitude = gain[0] * np.sin(2 * np.pi * frequency[0] * age)
                x0 = max(source_position[0]-1, 0);  x1 = min(source_position[0]+2, WIDTH)
                y0 = max(source_position[1]-1, 0);  y1 = min(source_position[1]+2, HEIGHT)
                sx0 = x0-(source_position[0]-1);    sx1 = 3-((source_position[0]+2)-x1)
                sy0 = y0-(source_position[1]-1);    sy1 = 3-((source_position[1]+2)-y1)
                next_wave[y0:y1, x0:x1] += amplitude * source_stencil[sy0:sy1, sx0:sx1]
            else:
                pulse_fired_time[0] = None

        # time advance 
        previous_wave = current_wave
        current_wave  = next_wave
        t[0] += 1
    # update wave display
    render_wave_pixel_by_pixel(current_wave, object_mask, rendered_frame)
    wave_image.set_data(rendered_frame)

    obj_w = object_half_width[0]  * 2
    obj_h = object_half_height[0] * 2
    info = (
        f"{'RUNNING':>20s}\n\n"
        f"  Source     ({source_position[0]:3d}, {source_position[1]:3d})\n"
        f"  Object     ({object_position[0]:3d}, {object_position[1]:3d})\n"
        f"  Obj size    {obj_w}x{obj_h} px\n"
        f"  Obj on      {'yes' if object_enabled[0] else 'no'}\n\n"
        f"  C           {C:.3f}\n"
        f"  K=C²        {K:.3f}\n"
        f"  Gain        {gain[0]:.2f}\n"
        f"  Duration    {pulse_duration[0]}\n"
        f"  Timestep    {t[0]}\n\n"
        f"  WASD     move source\n"
        f"  Arrows   move object\n"
        f"  Scroll   resize object\n"
        f"  Space    fire pulse\n"
        f"  G/F      gain up/down\n"
        f"  ]/[      duration\n"
        f"  E        object on/off\n"
        f"  R  reset   Q  quit"
    )
    info_text.set_text(info)
    return wave_image, info_text


fig.canvas.mpl_connect('button_press_event', on_click)
fig.canvas.mpl_connect('key_press_event',    on_key)
fig.canvas.mpl_connect('scroll_event',       on_scroll)

ani = FuncAnimation(fig, update, interval=20, blit=False, cache_frame_data=False)
plt.tight_layout()
plt.show()
