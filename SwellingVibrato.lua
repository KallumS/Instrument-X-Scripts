--[[
  Swelling Vibrato
  ----------------
  Draws a vibrato onto every selected note as pitch deviation points. The
  vibrato is an attenuated sine wave: it starts flat and the oscillation
  amplitude grows the longer the note is held, the way a singer eases into
  vibrato on a sustained note.

  Amplitude envelope: depth(t) = MAX_DEPTH_CENTS * (1 - exp(-t / RAMP_TAU)) ^ CURVE
  where t is seconds elapsed since the vibrato starts (i.e. after ONSET_DELAY).

  Tested against the Synthesizer V Studio script API, which Instrument X shares.
--]]

-- ---------------------------------------------------------------------------
-- Tweakables
-- ---------------------------------------------------------------------------

-- Seconds of dead-straight tone before any vibrato appears.
local ONSET_DELAY = 0.30

-- Time constant of the swell, in seconds. After RAMP_TAU the vibrato is at
-- ~63% of full depth, after 2x RAMP_TAU ~86%, after 3x ~95%.
local RAMP_TAU = 0.55

-- Extra shaping on the envelope. 1.0 is the plain exponential approach,
-- >1.0 holds the note straighter for longer before the swell takes over.
local CURVE = 1.4

-- Peak vibrato depth in cents (100 cents = 1 semitone). This is the deviation
-- either side of the note, so 50 gives a full sweep of one semitone.
local MAX_DEPTH_CENTS = 55

-- Vibrato speed in Hz at the start of the swell.
local RATE_HZ = 5.5

-- Speed at the far end of the swell, as a multiple of RATE_HZ. 1.0 keeps the
-- rate constant; 1.15 lets the vibrato tighten up slightly as it opens out.
local RATE_GROWTH = 1.0

-- Seconds of fade-out at the end of the note so the pitch lands back on target
-- instead of being cut off mid-swing.
local RELEASE = 0.08

-- Points drawn per vibrato cycle. Higher is smoother but heavier to edit.
local SAMPLES_PER_CYCLE = 12

-- Clear the note's built-in vibrato so the two don't stack up.
local DISABLE_BUILTIN_VIBRATO = true

-- ---------------------------------------------------------------------------

function getClientInfo()
  return {
    name = "Swelling Vibrato",
    category = "Pitch",
    author = "Kallum Shah",
    versionNumber = 1,
    minEditorVersion = 65540
  }
end

-- Amplitude of the swell at t seconds into the vibrato, 0..1.
local function swell(t)
  if t <= 0 then
    return 0
  end
  return (1 - math.exp(-t / RAMP_TAU)) ^ CURVE
end

-- Fade-out applied over the last RELEASE seconds of the note, 0..1.
local function release(secondsLeft)
  if RELEASE <= 0 or secondsLeft >= RELEASE then
    return 1
  end
  if secondsLeft <= 0 then
    return 0
  end
  -- Raised cosine, so the taper joins the sustained part without a corner.
  return 0.5 - 0.5 * math.cos(math.pi * secondsLeft / RELEASE)
end

-- Instantaneous vibrato rate at t seconds into the vibrato.
local function rateAt(t)
  if RATE_GROWTH == 1.0 then
    return RATE_HZ
  end
  return RATE_HZ * (1 + (RATE_GROWTH - 1) * swell(t))
end

local function vibratoOnNote(note, pitchDelta, timeAxis, groupOffset)
  local onsetBlick = note:getOnset()
  local endBlick = onsetBlick + note:getDuration()

  local onsetSec = timeAxis:getSecondsFromBlick(onsetBlick + groupOffset)
  local endSec = timeAxis:getSecondsFromBlick(endBlick + groupOffset)
  local startSec = onsetSec + ONSET_DELAY

  -- Nothing worth drawing on a note that is over before the vibrato begins.
  if endSec - startSec <= 0.02 then
    return false
  end

  -- Re-running the script on the same note should replace, not layer.
  pitchDelta:remove(onsetBlick, endBlick)

  -- Rounding to whole blicks can land two samples on the same position; keep
  -- the automation strictly ordered by dropping any that doesn't advance.
  local lastBlick = nil
  local function addPoint(seconds, cents)
    local blick = math.floor(timeAxis:getBlickFromSeconds(seconds) - groupOffset + 0.5)
    if lastBlick and blick <= lastBlick then
      return
    end
    lastBlick = blick
    pitchDelta:add(blick, cents)
  end

  -- Anchor the straight section so earlier pitch edits don't bleed in.
  addPoint(onsetSec, 0)
  addPoint(startSec, 0)

  local phase = 0
  local t = 0
  while true do
    local rate = rateAt(t)
    local dt = 1.0 / (rate * SAMPLES_PER_CYCLE)
    t = t + dt
    phase = phase + 2 * math.pi * rate * dt

    local seconds = startSec + t
    if seconds >= endSec then
      break
    end

    local depth = MAX_DEPTH_CENTS * swell(t) * release(endSec - seconds)
    addPoint(seconds, depth * math.sin(phase))
  end

  addPoint(endSec, 0)

  if DISABLE_BUILTIN_VIBRATO then
    note:setAttributes({dF0Vbr = 0})
  end

  return true
end

function main()
  local editor = SV:getMainEditor()
  local selection = editor:getSelection()
  local notes = selection:getSelectedNotes()

  if #notes == 0 then
    SV:showMessageBox("Swelling Vibrato", "Select at least one note first.")
    SV:finish()
    return
  end

  local groupRef = editor:getCurrentGroup()
  local pitchDelta = groupRef:getTarget():getParameter("pitchDelta")
  local timeAxis = SV:getProject():getTimeAxis()
  local groupOffset = groupRef:getTimeOffset()

  local done = 0
  for i = 1, #notes do
    if vibratoOnNote(notes[i], pitchDelta, timeAxis, groupOffset) then
      done = done + 1
    end
  end

  local skipped = #notes - done
  if done == 0 then
    SV:showMessageBox("Swelling Vibrato",
      "No vibrato drawn - every selected note is shorter than the " ..
      ONSET_DELAY .. "s onset delay.")
  elseif skipped > 0 then
    SV:showMessageBox("Swelling Vibrato",
      "Vibrato drawn on " .. done .. " note(s). " ..
      skipped .. " note(s) were too short and were left alone.")
  end

  SV:finish()
end
