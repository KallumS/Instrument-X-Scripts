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
