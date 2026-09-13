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

### FadingVibrato.lua — *Pitch → Fading Vibrato*

The mirror of Swelling Vibrato. Starts at full width and narrows as the note is
held, settling into a straight tone — the way a singer lets vibrato die away at
the end of a phrase.

```
depth(t) = MAX_DEPTH_CENTS * (1 - (1 - exp(-t / FADE_TAU)) ^ CURVE)
```

That is the swelling script's envelope subtracted from one, so the two are exact
counterparts and `CURVE` means the same thing in both.

Once the vibrato narrows past `STRAIGHT_THRESHOLD` it snaps to zero and the rest
of the note is written flat. Without that, an exponential decay never quite
reaches zero and the tail fills with a sub-cent wobble nobody can hear — at the
default a 3-second note goes genuinely straight for its last 0.85s, drawn with
two points rather than forty.

`ONSET_DELAY` defaults to `0.0` here, since "starts wavy" means from the first
moment. Everything else matches its sibling, except `RATE_DECAY` in place of
`RATE_GROWTH`: below 1.0 the vibrato slows as it narrows, which sounds more like
the singer relaxing than stopping.

| Constant | Default | What it does |
| --- | --- | --- |
| `ONSET_DELAY` | `0.0` | Seconds before the vibrato starts |
| `FADE_TAU` | `0.55` | Fade time constant; ~a third of full width after this long, essentially straight after 3x |
| `CURVE` | `1.4` | Higher holds the vibrato open longer before it collapses |
| `MAX_DEPTH_CENTS` | `55` | Starting deviation either side of the note |
| `RATE_HZ` | `5.5` | Vibrato speed at full width |
| `RATE_DECAY` | `1.0` | Speed once faded, as a multiple of `RATE_HZ`; below 1.0 slows as it narrows |
| `STRAIGHT_THRESHOLD` | `1.5` | Depth in cents below which the rest is written flat |
| `RELEASE` | `0.08` | Seconds of fade-out for notes that end before the vibrato has |
| `SAMPLES_PER_CYCLE` | `12` | Points drawn per vibrato cycle |
| `DISABLE_BUILTIN_VIBRATO` | `true` | Zero the note's own vibrato depth |


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

For a steeper late build use `CURVE = 3.0`. For a falling ramp use
`CurvedDecrescendo.lua` below, which reflects this curve in time rather than
just swapping the endpoints. Pointing `PARAMETER` at `"tension"` or
`"breathiness"` ramps those lanes instead, and the range clamp adapts
automatically.

### CurvedDecrescendo.lua — *Dynamics → Curved Decrescendo*

The mirror of Curved Crescendo, ramping Loudness from high down to low:

```
value(x) = START_VALUE + (END_VALUE - START_VALUE) * (1 - (1 - x) ^ CURVE)
```

The curve is the crescendo's reflected in time — verified point for point — so
it drops away quickly at first and then eases into the quiet, which is how a
sound left to decay actually behaves:

| through | crescendo | decrescendo |
| --- | --- | --- |
| 0% | −6.00 dB | +6.00 dB |
| 25% | −5.25 dB | +0.75 dB |
| 50% | −3.00 dB | −3.00 dB |
| 75% | +0.75 dB | −5.25 dB |
| 100% | +6.00 dB | −6.00 dB |

Set `CURVE` below 1.0 for the other kind of diminuendo, one that holds its
volume and drops late — at `0.5` it is still at +4.4 dB a quarter of the way
through, where the default has already fallen to +0.75 dB.

Constants are the same as Curved Crescendo's, with `START_VALUE` and `END_VALUE`
swapped to `6.0` and `-6.0`. The ramp machinery is byte-identical to its
sibling's; only the curve and the defaults differ.


### RemoveOverlaps.lua — *Notes → Remove Overlaps*

Makes the selected notes monophonic. Where a note runs past the start of the
next one, the earlier note is shortened to stop where the later one begins.

**Onsets are never moved.** Onsets carry the rhythm, so shortening the note that
overstayed keeps the performance intact — pushing the later note back instead
would drag everything after it out of time.

Only the selected notes are considered, so a phrase can be cleaned up without
disturbing the notes around it.

Notes sharing an onset are a special case: trimming the earlier one would leave
nothing of it, so it counts as swallowed whole and is deleted. Where two notes
share an onset the **longer one survives**. This is the only case where the
script deletes rather than shortens, and the summary always says how many went.
Set `REMOVE_ENGULFED = false` to keep them and have them reported as unresolved
instead — at the cost of the selection not being fully overlap-free afterwards.

| Constant | Default | What it does |
| --- | --- | --- |
| `GAP` | `0.0` | Seconds of silence left between notes; above 0 forces re-articulation |
| `MIN_DURATION` | `0.01` | Below this, a trimmed note counts as swallowed whole rather than overlapping |
| `REMOVE_ENGULFED` | `true` | Delete swallowed notes (`false` keeps and reports them) |
