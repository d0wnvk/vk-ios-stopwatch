# vk-ios-stopwatch

## Eye Break

The **Eye Break** screen is a repeating 30-second timer intended to remind the
user to rest their eyes. At the end of every 30-second round, the timer returns
to zero and plays a haptic pattern that identifies the completed round without
requiring the user to look at the screen.

### Controls

- **Start Timer** starts a new sequence from round 1.
- **Restart Timer** restarts both the timer and the haptic sequence from round 1.
- **Stop** stops the timer.
- **Reset** stops the timer, clears the event log, and resets the sequence to
  round 1.

### Haptic timing

Each buzz:

- lasts `100 ms`;
- uses maximum intensity (`1.0`);
- uses sharpness `0.9`.

Two buzzes in the same group start `180 ms` apart. Because each buzz lasts
`100 ms`, the silent gap between them is `80 ms`.

Groups start `550 ms` apart. A two-buzz group ends after `280 ms`, leaving a
`270 ms` silent pause before the next group starts.

Notation used below:

- `1` means one short buzz;
- `2` means two short buzzes separated by the short `80 ms` gap;
- `–` means the longer `270 ms` pause between groups.

### 16-round sequence

| Round | Elapsed time | Haptic pattern |
|------:|-------------:|----------------|
| 1 | 30 seconds | `1` |
| 2 | 60 seconds | `2` |
| 3 | 90 seconds | `2 – 1` |
| 4 | 120 seconds | `2 – 2` |
| 5 | 150 seconds | `2 – 2 – 1` |
| 6 | 180 seconds | `2 – 2 – 2` |
| 7 | 210 seconds | `2 – 2 – 2 – 1` |
| 8 | 240 seconds | `2 – 2 – 2 – 2` |
| 9 | 270 seconds | `2 – 2 – 2 – 2 – 1` |
| 10 | 300 seconds | `2 – 2 – 2 – 2 – 2` |
| 11 | 330 seconds | `2 – 2 – 2 – 2 – 2 – 1` |
| 12 | 360 seconds | `2 – 2 – 2 – 2 – 2 – 2` |
| 13 | 390 seconds | `2 – 2 – 2 – 2 – 2 – 2 – 1` |
| 14 | 420 seconds | `2 – 2 – 2 – 2 – 2 – 2 – 2` |
| 15 | 450 seconds | `2 – 2 – 2 – 2 – 2 – 2 – 2 – 1` |
| 16 | 480 seconds | `2 – 2 – 2 – 2 – 2 – 2 – 2 – 2` |

After round 16, the sequence repeats from round 1.

The app uses Core Haptics when the device supports it. If Core Haptics is
unavailable or fails, the same timing pattern is reproduced with heavy impact
feedback.

## Insta recorder

### Camera focus and exposure

The camera preview supports direct focus and exposure control:

- **Single tap** moves continuous autofocus and autoexposure to the selected
  point. A yellow reticle marks the selected point.
- **Long press** focuses and exposes at that point, then locks both settings.
  The yellow reticle displays a lock icon while AE/AF lock is selected.
- **Double tap** removes the reticle and restores centered continuous
  autofocus and autoexposure.

The reticle reports the inferred focus result:

- **Yellow** means the camera is adjusting focus.
- **Green** means focus stopped adjusting and appears to have settled.
- **Red** means focus was still adjusting after two seconds. Try moving farther
  from the subject, selecting another point, or changing zoom.

AVFoundation does not provide a definitive focus-failed result, so the red state
is based on a two-second timeout rather than an optical sharpness measurement.

Focus gestures are disabled while a scripted recording is running, preventing
focus changes from disturbing the programmed gimbal and zoom sequence. Set or
lock focus before starting a recording when a consistent cinematic focus is
required.

### Gimbal object tracking

Button **8. Track Object** arms selection for one drag. Draw a rectangle around
the object in the camera preview and release your finger to confirm it. The app
displays the rectangle in blue, starts Vision and gimbal tracking, and
automatically leaves selection mode. Further preview taps therefore return to
controlling focus and cannot accidentally replace the tracked object. Press
**8. Reselect Object** to arm one replacement drag.

Vision follows the selected image region and updates the blue rectangle about
15 times per second. Each observation and its camera frame are passed to
DockKit's custom-object tracking API, which generates the motor movement for the
Insta360 Flow 2 Pro. The current iPhone interface orientation is included so
DockKit maps horizontal and vertical image movement to the correct pan and tilt
axes. If tracking confidence becomes too low, the rectangle turns red. Tracking
starts immediately after selection and continues whether or not video recording
is active. While tracking is active, the tracker controls gimbal orientation
during a recording, so the scripted tilt is skipped; the recording's programmed
zoom still runs.

### Gimbal zoom wheel

When the Insta360 Flow 2 Pro is docked, its zoom wheel adjusts camera zoom in
`0.2×` increments. DockKit reports a positive event for zoom-in and a zero or
negative event for zoom-out. Wheel input is disabled during scripted recordings
to avoid conflicting with their programmed zoom animation. The zoom indicator
also shows the physical camera currently selected by the iPhone's virtual camera,
such as `Wide` or `Telephoto`. Its zoom value uses Apple's display multiplier so
it matches the scale shown by the native Camera app. Constituent-camera switching
uses AVFoundation's automatic policy, matching the native Camera app's lens
selection based on zoom, available light, and focus distance.

Each physical camera is also protected by a zoom-range gate derived from the
iPhone's `virtualDeviceSwitchOverVideoZoomFactors`. If focus or exposure forces
the virtual camera to fall back to a shorter lens, the app moves zoom into that
lens's optical range as well. For example, a close focus that changes Telephoto
to Wide may change `5.8×` to `4.9×`, avoiding an excessively cropped Wide image.

The zoom-range gate has these rules:

- It runs whenever AVFoundation reports that the active physical camera changed.
- Its lower and upper limits come from the connected iPhone's own virtual-camera
  switch-over factors rather than fixed values, so the limits can differ between
  iPhone models.
- If the current zoom is outside the newly selected camera's range, the app
  clamps it to the nearest boundary and shows the adjusted zoom in the status
  indicator.
- The gate runs only after AVFoundation reports a real physical-camera change.
  It does not clamp ordinary upward zoom before a switch-over boundary, because
  doing so would prevent the Wide camera from reaching the point where iOS can
  switch to Telephoto.
- It does not adjust zoom during an active recording, because changing zoom at
  that moment would create an unexpected visible jump in the recorded video.
