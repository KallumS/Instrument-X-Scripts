--[[
  Remove Overlaps
  ---------------
  Makes the selected notes monophonic by trimming away overlaps. Where a note
  runs past the start of the next one, the earlier note is shortened to stop
  where the later one begins.

  Onsets are never moved. Onsets carry the rhythm, so shortening the note that
  overstayed keeps the performance intact, where pushing the later note back
  would drag everything out of time.

  Only the selected notes are considered, so a selection can be cleaned up
  without disturbing the notes around it.

  Written against the Synthesizer V Studio script API, which Instrument X shares.
--]]

-- ---------------------------------------------------------------------------
-- Tweakables
-- ---------------------------------------------------------------------------

-- Seconds of silence to leave between consecutive notes. 0 makes trimmed notes
-- end exactly where the next begins; a small value forces re-articulation.
local GAP = 0.0

-- A note trimmed shorter than this is considered swallowed whole by its
-- neighbour rather than merely overlapping it, in seconds.
local MIN_DURATION = 0.01

-- What to do with a note that gets swallowed whole, which includes the case of
-- two notes sharing an onset. true deletes it, which is what it takes to leave
-- nothing overlapping. false keeps it and reports it as unresolved instead.
local REMOVE_ENGULFED = true

-- ---------------------------------------------------------------------------

function getClientInfo()
  return {
    name = "Remove Overlaps",
    category = "Notes",
    author = "Kallum Shah",
    versionNumber = 1,
    minEditorVersion = 65540
  }
end

function main()
  local editor = SV:getMainEditor()
  local notes = editor:getSelection():getSelectedNotes()

  if #notes < 2 then
    SV:showMessageBox("Remove Overlaps",
      "Select at least two notes - a single note can't overlap anything.")
    SV:finish()
    return
  end

  local groupRef = editor:getCurrentGroup()
  local group = groupRef:getTarget()
  local timeAxis = SV:getProject():getTimeAxis()
  local groupOffset = groupRef:getTimeOffset()

  -- Durations in seconds are tempo-dependent, so measure them where they land.
  local function blicksFor(seconds, atBlick)
    if seconds <= 0 then
      return 0
    end
    local startSec = timeAxis:getSecondsFromBlick(atBlick + groupOffset)
    return timeAxis:getBlickFromSeconds(startSec + seconds) - groupOffset - atBlick
  end

  -- Earliest first. Notes sharing an onset are ordered shortest first, so it's
  -- the shorter of the two that gets swallowed and the longer one that stays.
  table.sort(notes, function(a, b)
    if a:getOnset() ~= b:getOnset() then
      return a:getOnset() < b:getOnset()
    end
    return a:getDuration() < b:getDuration()
  end)

  local trimmed, unresolved = 0, 0
  local doomed = {}

  local previous = nil
  for i = 1, #notes do
    local note = notes[i]
    if previous then
      local previousEnd = previous:getOnset() + previous:getDuration()
      local limit = note:getOnset() - blicksFor(GAP, note:getOnset())

      if previousEnd > limit then
        local duration = limit - previous:getOnset()
        if duration >= blicksFor(MIN_DURATION, previous:getOnset()) then
          previous:setDuration(duration)
          trimmed = trimmed + 1
        elseif REMOVE_ENGULFED then
          doomed[#doomed + 1] = previous:getIndexInParent()
        else
          unresolved = unresolved + 1
        end
      end
    end
    previous = note
  end

  -- Removing a note renumbers everything after it, so work from the back.
  table.sort(doomed, function(a, b) return a > b end)
  for i = 1, #doomed do
    group:removeNote(doomed[i])
  end

  local parts = {}
  if trimmed > 0 then
    parts[#parts + 1] = "shortened " .. trimmed .. " note(s)"
  end
  if #doomed > 0 then
    parts[#parts + 1] = "deleted " .. #doomed .. " note(s) swallowed whole by a neighbour"
  end
  if unresolved > 0 then
    parts[#parts + 1] = unresolved ..
      " note(s) still overlap because they'd vanish entirely if trimmed"
  end

  if #parts == 0 then
    SV:showMessageBox("Remove Overlaps", "Nothing to do - none of the selected notes overlap.")
  else
    SV:showMessageBox("Remove Overlaps", "Done: " .. table.concat(parts, ", ") .. ".")
  end

  SV:finish()
end
