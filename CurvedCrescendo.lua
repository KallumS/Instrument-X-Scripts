--[[
  Curved Crescendo
  ----------------
  Ramps the Loudness parameter from a low value up to a high one along a power
  curve, so the swell builds gradually instead of climbing in a straight line.

  By default the ramp spans the whole selection, so selecting a phrase gives one
  crescendo across it. Set SPAN to "note" to give every selected note its own
  swell instead. With a single note selected the two are identical.

  Written against the Synthesizer V Studio script API, which Instrument X shares.
--]]

-- ---------------------------------------------------------------------------
-- Tweakables
-- ---------------------------------------------------------------------------

-- "selection" = one ramp across everything selected (a phrase crescendo).
-- "note"      = a separate ramp on each selected note.
local SPAN = "selection"

-- Start and end of the ramp, in the units the parameter shows in the editor
-- (decibels for Loudness). Values outside the parameter's legal range are
-- clamped, and the script tells you when that happened.
local START_VALUE = -6.0
local END_VALUE = 6.0

-- Curve shape. 1.0 is a straight line. Above 1.0 the ramp holds low and surges
-- late, which is the usual crescendo feel; below 1.0 it rises fast and eases
-- into the top. 2.0 is a gentle late build, 3.0 a steep one.
local CURVE = 2.0

-- Seconds spent easing away from the resting value into START_VALUE, so the
-- ramp doesn't begin with a step. Set to 0 to start hard at START_VALUE.
local LEAD_IN = 0.06

-- Seconds spent returning to the resting value after the ramp. Without this the
-- final value would carry on into whatever follows.
local RETURN_TIME = 0.12

-- Automation points drawn per second. The curve is sampled, so more points
-- track it more closely at the cost of a busier parameter lane.
local POINTS_PER_SECOND = 24

-- Which parameter to ramp. "loudness" is the dynamics lane; "tension",
-- "breathiness" and "voicing" also respond well to this treatment.
local PARAMETER = "loudness"

-- ---------------------------------------------------------------------------

function getClientInfo()
  return {
    name = "Curved Crescendo",
    category = "Dynamics",
    author = "Kallum Shah",
    versionNumber = 1,
    minEditorVersion = 65540
  }
end

-- Position along the ramp, 0..1 in, 0..1 out.
local function shape(x)
  if x <= 0 then
    return 0
  elseif x >= 1 then
    return 1
  end
  return x ^ CURVE
end

-- The editor knows each parameter's legal range and resting value, so ask it
-- rather than assuming. Older API versions may not answer, hence the fallback.
local function describeParameter(automation)
  local ok, def = pcall(function() return automation:getDefinition() end)
  if not ok or type(def) ~= "table" then
    return 0, nil, nil
  end
  local minValue, maxValue
  if type(def.range) == "table" then
    minValue, maxValue = def.range[1], def.range[2]
  end
  return def.defaultValue or 0, minValue, maxValue
end

local clamped = false

local function clamp(value, minValue, maxValue)
  if minValue and value < minValue then
    clamped = true
    return minValue
  end
  if maxValue and value > maxValue then
    clamped = true
    return maxValue
  end
  return value
end

-- Onset and end of the selection, in group-local blicks.
local function boundsOf(notes)
  local first = notes[1]:getOnset()
  local last = notes[1]:getOnset() + notes[1]:getDuration()
  for i = 2, #notes do
    local onset = notes[i]:getOnset()
    local finish = onset + notes[i]:getDuration()
    if onset < first then first = onset end
    if finish > last then last = finish end
  end
  return first, last
end

local function rampOver(onsetBlick, endBlick, automation, timeAxis, groupOffset, resting)
  local startSec = timeAxis:getSecondsFromBlick(onsetBlick + groupOffset)
  local endSec = timeAxis:getSecondsFromBlick(endBlick + groupOffset)
  local duration = endSec - startSec

  if duration <= 0 then
    return false
  end

  -- Rounding to whole blicks can land two samples on the same position; keep
  -- the automation strictly ordered by dropping any that doesn't advance.
  local lastBlick = nil
  local function addPoint(seconds, value)
    local blick = math.floor(timeAxis:getBlickFromSeconds(seconds) - groupOffset + 0.5)
    if lastBlick and blick <= lastBlick then
      return
    end
    lastBlick = blick
    automation:add(blick, value)
  end

  -- Wipe the range first so re-running replaces the ramp rather than fighting it.
  automation:remove(
    math.floor(timeAxis:getBlickFromSeconds(startSec - LEAD_IN) - groupOffset + 0.5),
    math.floor(timeAxis:getBlickFromSeconds(endSec + RETURN_TIME) - groupOffset + 0.5))

  -- Ease out of the resting value so the ramp doesn't open with a step.
  if LEAD_IN > 0 then
    local anchorBlick = timeAxis:getBlickFromSeconds(startSec - LEAD_IN) - groupOffset
    if anchorBlick >= 0 then
      addPoint(startSec - LEAD_IN, resting)
    end
  end

  -- Step by whole sample counts rather than accumulating a float interval, so
  -- the last sample can't drift onto the end point.
  local samples = math.max(1, math.ceil(duration * POINTS_PER_SECOND))
  for i = 0, samples - 1 do
    local x = i / samples
    addPoint(startSec + x * duration,
             START_VALUE + (END_VALUE - START_VALUE) * shape(x))
  end
  addPoint(endSec, END_VALUE)

  -- Fall back to the resting value, otherwise END_VALUE carries on into
  -- everything that follows.
  if RETURN_TIME > 0 then
    addPoint(endSec + RETURN_TIME, resting)
  end

  return true
end

function main()
  local editor = SV:getMainEditor()
  local notes = editor:getSelection():getSelectedNotes()

  if #notes == 0 then
    SV:showMessageBox("Curved Crescendo", "Select at least one note first.")
    SV:finish()
    return
  end

  local groupRef = editor:getCurrentGroup()
  local automation = groupRef:getTarget():getParameter(PARAMETER)
  local timeAxis = SV:getProject():getTimeAxis()
  local groupOffset = groupRef:getTimeOffset()

  local resting, minValue, maxValue = describeParameter(automation)
  START_VALUE = clamp(START_VALUE, minValue, maxValue)
  END_VALUE = clamp(END_VALUE, minValue, maxValue)

  local ramps = 0
  if SPAN == "note" then
    for i = 1, #notes do
      local onset = notes[i]:getOnset()
      if rampOver(onset, onset + notes[i]:getDuration(),
                  automation, timeAxis, groupOffset, resting) then
        ramps = ramps + 1
      end
    end
  else
    local first, last = boundsOf(notes)
    if rampOver(first, last, automation, timeAxis, groupOffset, resting) then
      ramps = 1
    end
  end

  if ramps == 0 then
    SV:showMessageBox("Curved Crescendo", "The selection has no length to ramp over.")
  elseif clamped then
    SV:showMessageBox("Curved Crescendo", string.format(
      "Drawn %d ramp(s), but the range was clipped to what %s accepts: %.1f to %.1f.",
      ramps, PARAMETER, START_VALUE, END_VALUE))
  end

  SV:finish()
end
