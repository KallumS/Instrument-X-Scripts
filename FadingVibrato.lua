--[[
  Fading Vibrato
  --------------
  The mirror of SwellingVibrato. Draws vibrato that starts at full width and
  narrows as the note is held, settling into a straight tone - the way a singer
  lets vibrato die away at the end of a phrase.

  Amplitude envelope: depth(t) = MAX_DEPTH_CENTS * (1 - (1 - exp(-t / FADE_TAU)) ^ CURVE)
  where t is seconds elapsed since the vibrato starts. That is the swelling
  script's envelope subtracted from one, so the two are exact counterparts and
  CURVE means the same thing in both.

  Once the vibrato has narrowed past STRAIGHT_THRESHOLD it is snapped to zero,
  so the tail of a long note is genuinely straight rather than a sub-cent
  wobble, and the parameter lane stays clean.

  Written against the Synthesizer V Studio script API, which Instrument X shares.
--]]

-- ---------------------------------------------------------------------------
-- Tweakables
-- ---------------------------------------------------------------------------

-- Seconds before the vibrato starts. 0 means it is there from the note's first
-- moment, which is what "starts wavy" usually wants.
local ONSET_DELAY = 0.0

-- Time constant of the fade, in seconds. After FADE_TAU the vibrato is down to
-- roughly a third of full width, after 2x FADE_TAU a tenth, after 3x it is
-- essentially straight.
local FADE_TAU = 0.55

-- Extra shaping on the envelope. 1.0 is the plain exponential decay; above 1.0
-- holds the vibrato open for longer before letting it collapse.
local CURVE = 1.4

-- Starting vibrato depth in cents (100 cents = 1 semitone). This is the
-- deviation either side of the note, so 55 sweeps just over a semitone.
local MAX_DEPTH_CENTS = 55

-- Vibrato speed in Hz at the start, while the vibrato is at full width.
local RATE_HZ = 5.5

-- Speed once the vibrato has faded out, as a multiple of RATE_HZ. 1.0 keeps the
-- rate constant; below 1.0 lets the vibrato slow down as it narrows, which
-- tends to sound like the singer relaxing rather than stopping.
local RATE_DECAY = 1.0

-- Below this depth in cents the vibrato is treated as finished and the rest of
-- the note is written flat. A wobble of a cent or two is well under what the
-- ear resolves, so cutting it there buys a genuinely straight tail instead of
-- a long stretch of inaudible points. Lower it to let the vibrato run longer.
local STRAIGHT_THRESHOLD = 1.5

-- Seconds of fade-out at the end of the note, for notes that end before the
-- vibrato has faded on its own.
local RELEASE = 0.08

-- Points drawn per vibrato cycle. Higher is smoother but heavier to edit.
local SAMPLES_PER_CYCLE = 12

-- Clear the note's built-in vibrato so the two don't stack up.
local DISABLE_BUILTIN_VIBRATO = true

-- ---------------------------------------------------------------------------

function getClientInfo()
  return {
    name = "Fading Vibrato",
    category = "Pitch",
    author = "Kallum Shah",
    versionNumber = 1,
    minEditorVersion = 65540
  }
end

-- Width of the vibrato at t seconds in, 1 at the start falling to 0.
local function fade(t)
  if t <= 0 then
    return 1
  end
  return 1 - (1 - math.exp(-t / FADE_TAU)) ^ CURVE
end

-- Fade-out applied over the last RELEASE seconds of the note, 0..1.
local function release(secondsLeft)
  if RELEASE <= 0 or secondsLeft >= RELEASE then
    return 1
  end
  if secondsLeft <= 0 then
    return 0
  end
  -- Raised cosine, so the taper joins the rest without a corner.
  return 0.5 - 0.5 * math.cos(math.pi * secondsLeft / RELEASE)
end

-- Instantaneous vibrato rate at t seconds in.
local function rateAt(t)
  if RATE_DECAY == 1.0 then
    return RATE_HZ
  end
  return RATE_HZ * (RATE_DECAY + (1 - RATE_DECAY) * fade(t))
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

  -- Anchor the note's start so earlier pitch edits don't bleed in. The sine
  -- begins at phase zero, so this is also where the vibrato starts from.
  addPoint(onsetSec, 0)
  if ONSET_DELAY > 0 then
    addPoint(startSec, 0)
  end

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

    local depth = MAX_DEPTH_CENTS * fade(t) * release(endSec - seconds)

    -- Once it has narrowed this far, call it straight and stop oscillating.
    if depth < STRAIGHT_THRESHOLD then
      addPoint(seconds, 0)
      break
    end

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
  local notes = editor:getSelection():getSelectedNotes()

  if #notes == 0 then
    SV:showMessageBox("Fading Vibrato", "Select at least one note first.")
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
    SV:showMessageBox("Fading Vibrato",
      "No vibrato drawn - every selected note is too short to fade over.")
  elseif skipped > 0 then
    SV:showMessageBox("Fading Vibrato",
      "Vibrato drawn on " .. done .. " note(s). " ..
      skipped .. " note(s) were too short and were left alone.")
  end

  SV:finish()
end
