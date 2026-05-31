# imports 
import numpy as np 
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches 
import matplotlib.gridspec as gridspec 
from matplotlib.animation import FuncAnimation 

# simulation space
WIDTH, HEIGHT = 320, 240 
BORDER = 50 

# emission 
C = 0.4 # wave speed in pixels per timestep
K = C * C # propoagation coefficient
frequency = [0.01] 
CYCLES = 1 # 1 complete wave 
pulse_duration= [int(CYCLES /frequency[0])] # how long the source stay on (how many timesteps is 1 cycle at the frequency

# object
shapes = ['circle', 'square', 'ellipse'] 
colormaps= ['RdBu_r', 'seismic', 'turbo']

source_position = [80, 120]
object_position = [200, 120]
receiver_position = [260, 120]

object_radius = [20]
object_shape = [0]

colormap_index = [0]

# echo detection 
gain = [0.8] # amplitude of sine wave 

paused = [False] # changed to true when pause pressed

pulse_fired_time = [None] # changed to current timestep when space is pressed
pulse_fired_timestep_global = [None] # used by the echo detector to remember when the shot happened (never gets cleared)
receiver_history_at_fire = [None] # records how many entries were in receiver history when pulse fired

expected_arrival_time_global = [None] 
expected_arrival_history = [None]

ECHO_WINDOW = 20 # begin search for peak +- 20 timesteps around predicted arrival 
ECHO_THRESHOLD = 0.03 # minimum peak amplitude to count as a detected echo 
echo_window_active= [False] # flips to true when time reaches the predicted echo arrival window, toggles the echo detector 
echo_window_closed = [False] # flips to true once the window has passed to prevent the detector from re-triggering outside of window 
peak_echo_value = [0.0] # if > threshold, echo detected. 
peak_echo_index = [None] # the history index when an echo is detected 
echo_detected = [False]
echo_measured_time = [None]
echo_missed = [False]

# grid 
yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH] # numpy allows two 2D arrays (rows), comparing element by element across the whole row at once 

# damping 
damping = np.ones((HEIGHT, WIDTH), np.float32) # this line creates a grid where every cell starts at value 1.0 = no absorption
for i in range(BORDER): # counts from 0 to 49, each value of i represents 1 strip of cells parallel to an edge, starting from the outermost strip at the edge and moving inward 
    v = np.sin(0.5 * np.pi * (i + 1) / BORDER) ** 2 # v is the multiplier applied to the wave. at i = 0 (outermost strip), v = 0 = wave killed = full absorption. at i = BORDER - 1 (innermost strip), v = 1 = wave unchanged = no absorption as it is near the simulation interior. 
    damping[i, :] = np.minimum(damping[i, :], v) # top edge (for every cell in the top row, set to whichever is smaller, current damping value or the new v )
    damping[HEIGHT-1-i, :] = np.minimum(damping[HEIGHT-1-i, :], v) # bottom edge 
    damping[:, i] = np.minimum(damping[:, i], v) # left edge 
    damping[:, WIDTH-1-i] = np.minimum(damping[:, WIDTH-1-i], v) # right edge 

# function to check if a pixel is inside the object or not
def make_object_mask(centre_x, centre_y, radius, shape): # inputs 
    if shape == 'circle':
        return ((xx-centre_x) ** 2 + (yy-centre_y) ** 2) <= radius ** 2
    elif shape == 'square':
        return (np.abs(xx-centre_x) <= radius) & (np.abs(yy-centre_y) <= radius)
    elif shape == 'ellipse':
        return ((xx - centre_x)**2 / radius**2 + (yy - centre_y)**2 / (radius * 0.5)**2) <= 1.0

# outline shape to visualise 
def make_patches(centre_x, centre_y, radius, shape):
    if shape == 'circle':
        return mpatches.Circle((centre_x, centre_y), radius, fill=False, color='white', lw=1.5, zorder=5)
    elif shape == 'square':
        return mpatches.Rectangle((centre_x - radius, centre_y - radius), 2*radius, 2*radius, fill=False, color='white', lw=1.5, zorder=5)
    elif shape == 'ellipse':
        return mpatches.Ellipse((centre_x, centre_y), 2*radius, radius, fill=False, color='white', lw=1.5, zorder=5)

# wave fields
previous_wave = np.zeros((HEIGHT, WIDTH), np.float32)
current_wave = np.zeros((HEIGHT, WIDTH), np.float32)
t = [0]
receiver_history = []
max_history = 600
object_mask = make_object_mask (object_position[0], object_position[1], object_radius[0], shapes[object_shape[0]]) # store grid region for object

# source stencil 
source_stencil = np.array([
    [0.05, 0.10, 0.05],
    [0.10, 1.00, 0.10],
    [0.05, 0.10, 0.05],
], dtype=np.float32)

source_stencil /= source_stencil.sum() # normalisation to keep the total energy correct

# display
# create the window
fig = plt.figure(figsize=(15, 6.5), facecolor='#0a0f1e')
fig.canvas.manager.set_window_title('Sonar Simulation — Pulsed Sonar Renderer')

# split the window into panels 
split_screen = gridspec.GridSpec(2, 2, width_ratios=[2.2, 1], hspace=0.4, wspace=0.3)
wave_simulation_panel  = fig.add_subplot(split_screen[:, 0])
graph_panel   = fig.add_subplot(split_screen[0, 1])
info_panel = fig.add_subplot(split_screen[1, 1])

# dark theme styling
for panel in [wave_simulation_panel, graph_panel, info_panel]:
    panel.set_facecolor('#0a0f1e')  # set background color of the panel to dark blue
    panel.tick_params(colors='#8899aa')  # set tick color to light blue
    for spine in panel.spines.values():
        spine.set_edgecolor('#223355')  # set border color to darker blue

# wave field image 
wave_simulation_panel.set_title('LClick=source  RClick=object  MClick=receiver  Space=fire [/]=radius  S=shape  C=colormap  P=pause  R=reset', color='#aabbcc', fontsize=8.5)
wave_simulation_panel.axis('off')

wave_image = wave_simulation_panel.imshow(current_wave, cmap='RdBu_r', vmin=-0.5, vmax=0.5, interpolation='bilinear', aspect='equal', extent=[0, WIDTH, HEIGHT, 0])

# markers 
source_point, = wave_simulation_panel.plot(source_position[0], source_position[1], '*', color='#ffe050', ms=14, label='Source', zorder=6)
receiver_point,  = wave_simulation_panel.plot(receiver_position[0],  receiver_position[1], 'D', color='#50ff90', ms=8, label='Receiver', zorder=6)
object_outline = [make_patches(object_position[0], object_position[1], object_radius[0], shapes[object_shape[0]])]
wave_simulation_panel.add_patch(object_outline[0])
wave_simulation_panel.legend(loc='upper right', fontsize=7, facecolor='#0a0f1e', labelcolor='#aabbcc', edgecolor='#223355')

# receiver graph 
graph_panel.set_title('Receiver — pressure vs time', color='#aabbcc', fontsize=9)
graph_panel.set_xlim(0, max_history)
graph_panel.set_ylim(-0.6, 0.6)
graph_panel.axhline(0, color='#223355', lw=0.8)
graph_panel.set_xlabel('timestep (since last reset)', color='#8899aa', fontsize=8)
graph_panel.set_ylabel('pressure', color='#8899aa', fontsize=8)
transmission_marker = graph_panel.axvline(x=0, color='#ffe050', lw=1.2, linestyle='--', alpha=0, label='TX')
receiver_marker = graph_panel.axvline(x=0, color='#ff6644', lw=1.2, linestyle='--', alpha=0, label='RX')
receiver_line, = graph_panel.plot([], [], color='#00ccff', lw=1)  # receiver signal line
graph_panel.legend(loc='upper right', fontsize=7, facecolor='#0a0f1e', labelcolor='#aabbcc', edgecolor='#223355')

# info text panel 
info_panel.axis('off')
info_text = info_panel.text(0.05, 0.98,'', transform=info_panel.transAxes, va='top', fontsize=7.5, family='monospace', color='#aabbcc')

# function to update object position and redraw the object when it is moved 
def rebuild_object():
    shape = shapes[object_shape[0]]
    object_mask[:] = make_object_mask(object_position[0], object_position[1], object_radius[0], shape)
    object_outline[0].remove()
    object_outline[0] = make_patches(object_position[0], object_position[1], object_radius[0], shape)
    wave_simulation_panel.add_patch(object_outline[0])

# echo detection function 
def echo_theory_time():
    dist_source_to_object   = np.sqrt((object_position[0] - source_position[0])**2 + (object_position[1] - source_position[1])**2)
    dist_object_to_receiver = np.sqrt((receiver_position[0] - object_position[0])**2 + (receiver_position[1] - object_position[1])**2)
    return (dist_source_to_object + dist_object_to_receiver) / C, dist_source_to_object, dist_object_to_receiver

# function to reset all echo detection state back to default 
def clear_receiver_state(clear_tx=True):
    receiver_history.clear()
    echo_detected[0]      = False
    echo_measured_time[0] = None
    echo_missed[0]        = False
    echo_window_active[0] = False
    echo_window_closed[0] = False
    peak_echo_value[0]    = 0.0
    peak_echo_index[0]    = None
    receiver_marker.set_alpha(0)
    if clear_tx:
        pulse_fired_time[0]             = None
        pulse_fired_timestep_global[0]  = None
        receiver_history_at_fire[0]     = None
        expected_arrival_time_global[0] = None
        expected_arrival_history[0]     = None
        transmission_marker.set_alpha(0)

# mouse clcik event handler for setting source, object, receiver positions 
def on_click(event):
    if event.inaxes != wave_simulation_panel or event.xdata is None:
        return
    new_x = int(np.clip(event.xdata, 0, WIDTH-1))
    new_y = int(np.clip(event.ydata, 0, HEIGHT-1))
    if event.button == 1:# left click to set new source position
        source_position[0], source_position[1] = new_x, new_y
        source_point.set_data([new_x], [new_y])
        clear_receiver_state()
    elif event.button == 2: # middle click to set new receiver position 
        receiver_position[0], receiver_position[1] = new_x, new_y
        receiver_point.set_data([new_x], [new_y])
        clear_receiver_state()
    elif event.button == 3: # right click to set new object position 
        object_position[0], object_position[1] = new_x, new_y
        rebuild_object()
        clear_receiver_state()
    fig.canvas.draw_idle()

# keyboard event handler 
def on_key(event):
    if event.key == ' ':
        if pulse_fired_time[0] is None:
            clear_receiver_state(clear_tx=False)
            pulse_fired_time[0]             = t[0]
            pulse_fired_timestep_global[0]  = t[0]
            receiver_history_at_fire[0]     = len(receiver_history)
            echo_t_theory                   = echo_theory_time()[0]
            expected_arrival_time_global[0] = pulse_fired_timestep_global[0] + echo_t_theory
            expected_arrival_history[0]     = receiver_history_at_fire[0] + echo_t_theory
            transmission_marker.set_xdata([len(receiver_history)])
            transmission_marker.set_alpha(0.8)
    elif event.key == 'r':
        previous_wave[:] = 0
        current_wave[:] = 0
        t[0] = 0
        clear_receiver_state()
    elif event.key == 'p':
        paused[0] = not paused[0]
    elif event.key in ('+', '='):
        gain[0] = min(gain[0] + 0.1, 2.0)
    elif event.key == '-':
        gain[0] = max(gain[0] - 0.1, 0.05)
    elif event.key == 'up':
        frequency[0] = max(round(frequency[0] - 0.002, 4), 0.004)
        pulse_duration[0] = int(CYCLES / frequency[0])
        clear_receiver_state()
    elif event.key == 'down':
        frequency[0] = min(round(frequency[0] + 0.002, 4), 0.1)
        pulse_duration[0] = int(CYCLES / frequency[0])
        clear_receiver_state()
    elif event.key == ']':
        object_radius[0] = min(object_radius[0] + 2, 80)
        rebuild_object(); clear_receiver_state()
    elif event.key == '[':
        object_radius[0] = max(object_radius[0] - 2, 4)
        rebuild_object(); clear_receiver_state()
    elif event.key == 's':
        object_shape[0] = (object_shape[0] + 1) % len(shapes)
        rebuild_object(); clear_receiver_state()
    elif event.key == 'c':
        colormap_index[0] = (colormap_index[0] + 1) % len(colormaps)
        wave_image.set_cmap(colormaps[colormap_index[0]])
    elif event.key in ('q', 'escape'):
        plt.close('all')

STEPS_PER_FRAME = 4 # runs 4 physics steps per displayed frame. 

def update(_):
    
    # if pause pressed, skip the update and just return current display state  
    if paused[0]:
        return wave_image, receiver_line, transmission_marker, receiver_marker, info_text, source_point, receiver_point

    global previous_wave, current_wave

    for _ in range(STEPS_PER_FRAME):
        next_wave = np.empty_like(current_wave)
        centre    = current_wave[1:-1, 1:-1]

        # rigid BC — Neumann fake cell
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

        # Neumann edges — no reflection at grid boundary
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

        # receiver sampling
        receiver_value = float(current_wave[receiver_position[1], receiver_position[0]])
        receiver_history.append(receiver_value)

        # echo detection
        if receiver_history_at_fire[0] is not None and expected_arrival_history[0] is not None:
            index_now   = len(receiver_history) - 1
            window_start = expected_arrival_history[0] - ECHO_WINDOW
            window_end   = expected_arrival_history[0] + ECHO_WINDOW
            if window_start <= index_now <= window_end:
                echo_window_active[0] = True
                if abs(receiver_value) > peak_echo_value[0]:
                    peak_echo_value[0] = abs(receiver_value)
                    peak_echo_index[0] = index_now
            elif index_now > window_end and echo_window_active[0] and not echo_window_closed[0]:
                echo_window_closed[0] = True
                if peak_echo_value[0] > ECHO_THRESHOLD:
                    echo_measured_time[0] = peak_echo_index[0]
                    echo_detected[0]      = True
                    receiver_marker.set_xdata([peak_echo_index[0]])
                    receiver_marker.set_alpha(0.8)
                else:
                    echo_missed[0] = True

    # update wave display
    wave_image.set_data(current_wave)

    # update receiver graph
    n = len(receiver_history)
    if n > 1:
        start = max(0, n - max_history)
        receiver_line.set_data(list(range(start, n)), receiver_history[start:n])
        graph_panel.set_xlim(start, max(start + max_history, n))

    # update info text
    wavelength   = C / frequency[0]
    object_over_wavelength = (2 * object_radius[0]) / wavelength
    echo_t_theory, dist_so, dist_or = echo_theory_time()

    transmission_string   = f"t={transmission_marker.get_xdata()[0]:.0f}" if transmission_marker.get_alpha() > 0 else "not fired"
    echo_string = (f"t={echo_measured_time[0]}" if echo_detected[0] else
                ("not detected"  if echo_missed[0] else
                 ("listening..." if transmission_marker.get_alpha() > 0 else "—")))

    info = (
        f"{'PAUSED' if paused[0] else 'RUNNING':>22s}\n\n"
        f"  Source     ({source_position[0]:3d}, {source_position[1]:3d})\n"
        f"  Object     ({object_position[0]:3d}, {object_position[1]:3d})\n"
        f"  Receiver   ({receiver_position[0]:3d}, {receiver_position[1]:3d})\n"
        f"  Shape       {shapes[object_shape[0]]}\n"
        f"  Radius      {object_radius[0]}px\n\n"
        f"  C           {C:.3f}\n"
        f"  K=C²        {K:.3f}\n"
        f"  Gain        {gain[0]:.2f}\n"
        f"  Wavelength  {wavelength:.0f}px\n"
        f"  obj/λ       {object_over_wavelength:.2f}x\n"
        f"  Timestep    {t[0]}\n\n"
        f"  TX fired    {transmission_string}\n"
        f"  Echo meas.  {echo_string}\n"
        f"  Echo theory t≈{echo_t_theory:.0f}\n\n"
        f"  dist src→obj  {dist_so:.1f}px\n"
        f"  dist obj→rx   {dist_or:.1f}px\n\n"
        f"  LClick   move source\n"
        f"  RClick   move object\n"
        f"  MClick   move receiver\n"
        f"  [  /  ]  radius\n"
        f"  S        cycle shape\n"
        f"  C        colormap\n"
        f"  Space    fire pulse\n"
        f"  +/-      gain\n"
        f"  ↑ / ↓    wavelength\n"
        f"  P  pause   R  reset   Q  quit"
    )
    info_text.set_text(info)
    return wave_image, receiver_line, transmission_marker, receiver_marker, info_text, source_point, receiver_point

fig.canvas.mpl_connect('button_press_event', on_click)
fig.canvas.mpl_connect('key_press_event',    on_key)

ani = FuncAnimation(fig, update, interval=20, blit=False, cache_frame_data=False)
plt.tight_layout()
plt.show()