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
