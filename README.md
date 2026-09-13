# Instrument X Scripts

Scripts for Dreamtonics Instrument X, written against the Synthesizer V Studio
script API that Instrument X shares.

## Installation

Copy the `.lua` file into your scripts folder, then use **Scripts → Rescan** in
the editor. The script then appears under the category it declares.

## Scripts

### SwellingVibrato.lua — *Pitch → Swelling Vibrato*

Draws vibrato onto every selected note as pitch deviation points. The note
starts dead straight, and the oscillation widens the longer it is held — an
attenuated sine wave, the way a singer eases into vibrato on a sustain.

The depth envelope is an exponential approach with an extra shaping exponent:

```
depth(t) = MAX_DEPTH_CENTS * (1 - exp(-t / RAMP_TAU)) ^ CURVE
```

where `t` is seconds elapsed since the vibrato starts.

The note's built-in vibrato is zeroed so the two don't stack, existing pitch
deviation inside the note is cleared first so the script is safe to re-run, and
the last few milliseconds taper back to zero so the pitch lands on target
instead of being cut off mid-swing. Notes too short to fit the onset delay are
left untouched.

All settings are constants at the top of the file:

| Constant | Default | What it does |
| --- | --- | --- |
| `ONSET_DELAY` | `0.30` | Seconds of straight tone before any vibrato |
| `RAMP_TAU` | `0.55` | Swell time constant; ~63% depth after this long, ~95% after 3x |
| `CURVE` | `1.4` | Extra shaping; higher holds the note straighter for longer |
| `MAX_DEPTH_CENTS` | `55` | Peak deviation either side of the note (100 cents = 1 semitone) |
| `RATE_HZ` | `5.5` | Vibrato speed |
| `RATE_GROWTH` | `1.0` | Speed at full swell as a multiple of `RATE_HZ`; `1.0` keeps it constant |
| `RELEASE` | `0.08` | Seconds of fade-out at the note end |
| `SAMPLES_PER_CYCLE` | `12` | Points drawn per vibrato cycle |
| `DISABLE_BUILTIN_VIBRATO` | `true` | Zero the note's own vibrato depth |

For a slower, wider opera-style swell try `RAMP_TAU = 1.0`, `MAX_DEPTH_CENTS =
80`, `RATE_HZ = 5.0`. For a tighter pop delivery, `ONSET_DELAY = 0.15`,
`RAMP_TAU = 0.3`, `MAX_DEPTH_CENTS = 35`.

### CurvedCrescendo.lua — *Dynamics → Curved Crescendo*

Ramps the Loudness parameter from a low value up to a high one along a power
curve, so the swell builds gradually rather than climbing in a straight line.

```
value(x) = START_VALUE + (END_VALUE - START_VALUE) * x ^ CURVE
```

where `x` runs 0 to 1 across the ramp. With the defaults the first quarter of
the ramp gains under a decibel while the last quarter gains over five, which is
the shape of a crescendo that arrives rather than one that merely rises.

By default the ramp spans the **whole selection**, so selecting a phrase gives
one crescendo across it, gaps between notes included. Set `SPAN` to `"note"` for
a separate swell on each selected note. With one note selected the two modes are
identical.

The script reads the parameter's legal range from the editor and clamps to it,
saying so if your values were out of range. It eases out of the resting value at
the start instead of stepping into it, and returns to the resting value after
the ramp — without that, the final loudness would carry on into everything
downstream. Re-running clears the range first, so it replaces rather than layers.

| Constant | Default | What it does |
| --- | --- | --- |
| `SPAN` | `"selection"` | `"selection"` for one phrase-wide ramp, `"note"` for one per note |
| `START_VALUE` | `-6.0` | Where the ramp begins, in the editor's units (dB for Loudness) |
| `END_VALUE` | `6.0` | Where it ends |
| `CURVE` | `2.0` | `1.0` is a straight line; above holds low and surges late, below rises fast then eases |
| `LEAD_IN` | `0.06` | Seconds easing from the resting value into `START_VALUE` |
| `RETURN_TIME` | `0.12` | Seconds returning to the resting value afterwards |
| `POINTS_PER_SECOND` | `24` | Automation points drawn per second |
| `PARAMETER` | `"loudness"` | Which lane to ramp |

For a steeper late build use `CURVE = 3.0`. For a *decrescendo*, swap the two
values (`START_VALUE = 6.0`, `END_VALUE = -6.0`) — the curve still eases in the
same direction, so pair it with `CURVE = 0.5` for a natural fall. Pointing
`PARAMETER` at `"tension"` or `"breathiness"` ramps those lanes instead, and the
range clamp adapts automatically.
