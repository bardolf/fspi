-- Doplněk k ~/scripts/pip_play.sh (živý přenos v PiP okně).
--
-- pip_play.sh dá mpv statický VOD snímek HLS playlistu, aby fungovalo přesné
-- převíjení. Snímek ale končí na živé hraně z okamžiku stažení, takže tam
-- přehrávání skončí, i když přenos běží dál. Tenhle skript si v tu chvíli
-- (a taky když se přehrávání rozbije chybou) řekne o novější snímek a naváže
-- na stejné pozici. Pozice jsou mezi snímky srovnatelné — každý snímek začíná
-- na začátku přenosu.
--
-- Konfigurace přes env, ne --script-opts: URL může obsahovat čárku.

local mp = require 'mp'

local url      = os.getenv("PIP_URL")
local helper   = os.getenv("PIP_HELPER")
local snapshot = os.getenv("PIP_SNAPSHOT")

local last_pos  = 0     -- kde jsme skončili
local prev_pos  = -1    -- pozice při předchozím navázání
local stalls    = 0     -- kolikrát po sobě navázání nepřineslo nic nového
local resume_to = nil

mp.observe_property("time-pos", "number", function(_, value)
  if value then last_pos = value end
end)

mp.register_event("file-loaded", function()
  if resume_to then
    mp.commandv("seek", resume_to, "absolute")
    resume_to = nil
  end
end)

local function resume()
  -- playback_only=false, ať proces přežije i to, že zrovna nic nehraje.
  mp.command_native_async({
    name = "subprocess",
    playback_only = false,
    args = { helper, "--snapshot", url, snapshot },
  }, function(ok, res)
    if not ok or not res or res.status ~= 0 then
      mp.osd_message("PiP: novější část přenosu se nepodařilo načíst", 4)
      mp.commandv("quit")
      return
    end
    resume_to = last_pos
    mp.commandv("loadfile", snapshot, "replace")
  end)
end

mp.register_event("end-file", function(event)
  -- "quit"/"stop" znamená uživatele; navazujeme jen na konec snímku a chyby.
  if event.reason ~= "eof" and event.reason ~= "error" then return end
  if not (url and helper and snapshot) then return end

  -- Když jsme se od posledního navázání nikam nedostali, přenos buď skončil,
  -- nebo se zasekl. Pár pokusů s pauzou, pak to vzdáme.
  if last_pos <= prev_pos + 1 then
    stalls = stalls + 1
  else
    stalls = 0
  end
  prev_pos = last_pos

  if stalls >= 3 then
    mp.osd_message("PiP: přenos už nepokračuje", 4)
    mp.commandv("quit")
    return
  end

  mp.add_timeout(stalls > 0 and 15 or 1, resume)
end)
