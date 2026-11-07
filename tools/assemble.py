#!/usr/bin/env python3
"""Assemble the one ForeverGPS addon folder from its parts.

    python tools/assemble.py            # build/assembled/ForeverGPS
    python tools/assemble.py --quiet

The vendored addons stay byte-exact at their pins in addons/, where their own test
suites run and upstream updates land. This builds what ships: one addon whose TOC
loads their real files, in their real order, under Vendor/, followed by Forever-GPS.

What one folder changes for them is written down here and nowhere else:

  EDITS       exact replacements, each of which must match as often as it says, so
              an upstream change cannot slip past unnoticed
  paths       Interface\\AddOns\\EasyFind\\... moves under Vendor\\
  namespaces  all files of one addon share one private table. EasyFind and GPS
              already share theirs. The Questie extension's stays apart

Companion apps are left out: they are a search bar's utilities, and nothing in
navigation reaches them. EXCLUDED_PREFIXES lists the rest of what stays behind.

Standard library only. It makes a local folder and publishes nothing.
"""
from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ROOT / "addons"
OUT = ROOT / "build" / "assembled" / "ForeverGPS"
SCRIPT = Path(__file__).resolve()

VENDORS = ("EasyFind", "EasyFind_GPS", "EasyFind_Questie")
# Art and fonts that travel with the code. Everything else is copied because a TOC
# names it.
ASSET_SUFFIXES = {".tga", ".blp", ".ttf", ".otf", ".ogg", ".mp3", ".png"}
EXCLUDED_PREFIXES = {
    # The search bar's companions, its tutorial art, its development files.
    "EasyFind": ("Apps/", "Onboarding/", "tests/", "API/", "Guide/Images/"),
    "EasyFind_GPS": ("tests/",),
    "EasyFind_Questie": ("tools/", "tests/"),
}
# Files a TOC lists that have no place in one folder.
LEFT_OUT = {
    # Asks the game about an addon called EasyFind, to check its version. There is none,
    # and the version is the one built in.
    "EasyFind_GPS": ("Guard.lua",),
    # Tells players of a newer EasyFind, heard from guildmates. Every caller checks for
    # it, and an update here is not theirs to announce.
    "EasyFind": ("Core/VersionCheck.lua",),
}
LICENSE_FILES = ("LICENSE",)

RULE = re.compile(r"\[(\w+)\s+([^\]]+)\]")
PATHS = re.compile(r"Interface(\\\\|\\|/)AddOns\1(EasyFind(?:_GPS|_Questie)?)\1")

# What keeps the game's quest pins out of our name: docs/TAINT.md has the reasoning.
# A super-track change fires its event inside the call, which rebuilds the quest pins in
# the caller's taint, even with the map closed once it has been opened. In a fight that
# is the protected call refused. So every change to the game's waypoint and tracking goes
# through one door, which holds it through a fight as well as an open map, skips one
# that changes nothing, and leaves the native pins alone.
TAINT_EDITS = [
    ("EasyFind", "MapSearch/Navigation.lua",
     """function MapSearch.WaypointChange(kind, fn)
    if WorldMapFrame and WorldMapFrame:IsShown() then
        waypointWaits[kind] = fn
        return
    end
    waypointWaits[kind] = nil
    fn()
end
""",
     """local changes = { ran = 0, heldInCombat = 0, heldUnderMap = 0, skipped = 0, mapTurns = 0, mapRefused = 0 }
MapSearch.WaypointChanges = changes
local function HoldFor()
    if InCombatLockdown() then return "heldInCombat" end
    if WorldMapFrame and WorldMapFrame:IsShown() then return "heldUnderMap" end
    return nil
end
function MapSearch.WaypointChange(kind, fn)
    local hold = HoldFor()
    if hold then
        changes[hold] = changes[hold] + 1
        waypointWaits[kind] = fn
        return
    end
    waypointWaits[kind] = nil
    changes.ran = changes.ran + 1
    fn()
end
""", 1),
    ("EasyFind", "MapSearch/Navigation.lua",
     """local function RunWaypointWaits()
    for _, kind in ipairs(WAYPOINT_WAIT_ORDER) do
        local fn = waypointWaits[kind]
        waypointWaits[kind] = nil
        if fn then fn() end
    end
end
""",
     """local function RunWaypointWaits()
    if HoldFor() then return end
    for _, kind in ipairs(WAYPOINT_WAIT_ORDER) do
        local fn = waypointWaits[kind]
        waypointWaits[kind] = nil
        if fn then
            changes.ran = changes.ran + 1
            fn()
        end
    end
end
do
    local afterCombat = CreateFrame("Frame")
    afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
    afterCombat:SetScript("OnEvent", RunWaypointWaits)
end

-- The game's waypoint taken off, if it is still the one this was asked about: one
-- waiting out a fight must not take a waypoint the player dropped meanwhile.
function MapSearch.ClearGameWaypoint()
    local was = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    MapSearch.WaypointChange("place", function()
        local now = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        if not now then return end
        if was and was.position and now.position and (now.uiMapID ~= was.uiMapID
            or math.abs(now.position.x - was.position.x) > 0.0001 or math.abs(now.position.y - was.position.y) > 0.0001) then
            return
        end
        ClearUserWaypoint()
    end)
end

-- The super-track, changed only when that changes something. With the beacon turned off
-- it is only ever let go of, so a session with it off makes no refresh in our name.
function MapSearch.TrackChange(on)
    on = on and true or false
    if on and MapSearch.beaconOff then return end
    MapSearch.WaypointChange("track", function()
        if on and MapSearch.beaconOff then return end
        if (C_SuperTrack.IsSuperTrackingUserWaypoint() and true or false) == on then
            changes.skipped = changes.skipped + 1
            return
        end
        C_SuperTrack.SetSuperTrackedUserWaypoint(on)
    end)
end

-- The one door to the game's map, for a click in the map's own panel. An id written from
-- here stays tainted for every refresh that reads it, so never in a fight, and never to
-- the map it is already on. Forever-GPS itself does not come through here at all.
function MapSearch.TurnMap(mapID)
    if not (WorldMapFrame and mapID) or WorldMapFrame:GetMapID() == mapID then return end
    if InCombatLockdown() then
        changes.mapRefused = changes.mapRefused + 1
        return
    end
    changes.mapTurns = changes.mapTurns + 1
    WorldMapFrame:SetMapID(mapID)
end
""", 1),
    ("EasyFind", "MapSearch/Navigation.lua",
     """    if WAYPOINTS then MapSearch.WaypointChange("track", function() C_SuperTrack.SetSuperTrackedUserWaypoint(on) end) end
""",
     """    if WAYPOINTS then MapSearch.TrackChange(on) end
""", 1),
    ("EasyFind", "MapSearch/Navigation.lua",
     """        TrackWaypoint(false)
        if WAYPOINTS and HasUserWaypoint() then
            ClearUserWaypoint()
        end
""",
     """        TrackWaypoint(false)
        if WAYPOINTS and HasUserWaypoint() then
            MapSearch.ClearGameWaypoint()
        end
""", 1),
    ("EasyFind", "MapSearch/Navigation.lua", "WorldMapFrame:SetMapID(targetMapID)", "MapSearch.TurnMap(targetMapID)", 1),
    ("EasyFind", "MapSearch/Navigation.lua", "WorldMapFrame:SetMapID(data.zoneMapID)", "MapSearch.TurnMap(data.zoneMapID)", 3),
    ("EasyFind", "MapSearch/Navigation.lua", "WorldMapFrame:SetMapID(spotMapID)", "MapSearch.TurnMap(spotMapID)", 1),
    ("EasyFind", "MapSearch/UINavigation.lua", "WorldMapFrame:SetMapID(data.entranceMapID)", "MapSearch.TurnMap(data.entranceMapID)", 1),
    ("EasyFind", "MapSearch/UINavigation.lua", "WorldMapFrame:SetMapID(data.zoneMapID)", "MapSearch.TurnMap(data.zoneMapID)", 1),
    ("EasyFind", "MapSearch/UINavigation.lua", "WorldMapFrame:SetMapID(data.mapID)", "MapSearch.TurnMap(data.mapID)", 1),
    # The native pin stays as the game draws it: a second mark under ours is a small price
    # for writing nothing onto a pooled pin of the game's.
    ("EasyFind", "MapSearch/Navigation.lua",
     """local function SyncGameWaypointPin()
    local mx, my
""",
     """local function SyncGameWaypointPin()
    do return end
    local mx, my
""", 1),
    ("EasyFind", "MapSearch/Navigation.lua",
     """        if WAYPOINTS then
            since = 0.05
            pinWatch:SetScript("OnUpdate", WatchPins)
        end
""", "", 1),
    # What a native pin's scale was, held here rather than on the pin.
    ("EasyFind", "MapSearch/Pins.lua",
     """local highlightedNativePin = nil
""",
     """local highlightedNativePin = nil
local nativePinScales = setmetatable({}, { __mode = "k" })
""", 1),
    ("EasyFind", "MapSearch/Pins.lua",
     """    if p._easyfindOriginalScale and p.SetScale then
        pcall(p.SetScale, p, p._easyfindOriginalScale)
    end
    p._easyfindOriginalScale = nil
""",
     """    if nativePinScales[p] and p.SetScale then
        pcall(p.SetScale, p, nativePinScales[p])
    end
    nativePinScales[p] = nil
""", 1),
    ("EasyFind", "MapSearch/Pins.lua",
     """        pin._easyfindOriginalScale = pin._easyfindOriginalScale or (pin:GetScale() or 1)
        pcall(pin.SetScale, pin, pin._easyfindOriginalScale * nativePinScale)
""",
     """        nativePinScales[pin] = nativePinScales[pin] or (pin:GetScale() or 1)
        pcall(pin.SetScale, pin, nativePinScales[pin] * nativePinScale)
""", 1),
    ("EasyFind_GPS", "GPS.lua", "    if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end\n",
     "    if ns.MapSearch and ns.MapSearch.ClearGameWaypoint then ns.MapSearch.ClearGameWaypoint() end\n", 2),
    ("EasyFind_GPS", "GPS.lua",
     """    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        GPS.GamePinChange("track", function() C_SuperTrack.SetSuperTrackedUserWaypoint(on) end)
    end
""",
     """    local MS = ns.MapSearch
    if MS and MS.TrackChange and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then MS.TrackChange(on) end
""", 1),
    ("EasyFind_GPS", "GPS.lua",
     """    local ST = C_SuperTrack
    if ST and ST.IsSuperTrackingQuest and ST.IsSuperTrackingQuest() and ST.SetSuperTrackedQuestID then
""",
     """    local ST = C_SuperTrack
    if ns.MapSearch and ns.MapSearch.beaconOff then return end
    if ST and ST.IsSuperTrackingQuest and ST.IsSuperTrackingQuest() and ST.SetSuperTrackedQuestID then
""", 1),
    # The beacon coming back, for the step under way.
    ("EasyFind_GPS", "GPS.lua", "local function ToggleRouteTracking()\n",
     """function GPS.RetrackActive()
    local route = Route()
    if route and not route.arrived and not route.untracked then TrackStep(route.active or 1) end
end

local function ToggleRouteTracking()
""", 1),
    ("EasyFind_GPS", "MapClick.lua",
     "if map:IsShown() and map:GetMapID() ~= p.mapID then map:SetMapID(p.mapID) end",
     "if map:IsShown() and ns.MapSearch then ns.MapSearch.TurnMap(p.mapID) end", 1),
    ("EasyFind_GPS", "Preview.lua",
     "if mapID and here ~= mapID and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID) end",
     "if mapID and here ~= mapID and ns.MapSearch then ns.MapSearch.TurnMap(mapID) end", 1),
    # The GPS is always here, so nothing reached this: the only setters left outside the door.
    ("EasyFind_Questie", "Quests.lua",
     """    elseif C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(dest.mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(dest.mapID, dest.x, dest.y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
""",
     """    end
""", 1),
]

# (addon, file, old, new, how many times). {version} is that addon's own.
EDITS = [
    # Settled the moment it has its settings, before anything reads them, in a way that
    # cannot depend on which frame hears ADDON_LOADED first.
    ("EasyFind", "Core/Main.lua", "    EasyFind.db = EasyFindDB\n    -- The profile this character",
     "    EasyFind.db = EasyFindDB\n    ForeverGPSPreflight.Settle(EasyFindDB)\n    -- The profile this character", 1),
    # Two seconds after login it loads every spell, toy, mount and setting for its search
    # bar. That bar stays hidden here and navigation reads none of it.
    ("EasyFind", "Core/Main.lua", "    if ns.Database and ns.Utils and ns.Utils.SafeAfter then\n        ns.Utils.SafeAfter(2, function()",
     "    if EasyFind.db.visible ~= false and ns.Database and ns.Utils and ns.Utils.SafeAfter then\n        ns.Utils.SafeAfter(2, function()", 1),
    # An EasyFind page in the game's addon settings, opening a panel that is not here.
    ("EasyFind", "Core/Main.lua", "local regOk, regErr = xpcall(RegisterBlizzardOptionsStub, ErrorHandler)",
     "local regOk, regErr = true, nil", 1),
    # Its version is its own, not the folder's: its upgrade notes compare against it.
    ("EasyFind", "Core/Main.lua", 'ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")',
     'ns.version = "{version}"', 1),
    # The GPS is here whatever the addon list says. These decide whether EasyFind
    # thinks it has a GPS at all.
    ("EasyFind", "Search/Modules.lua", "function ns.IsCompanionLoadable(name)\n",
     'function ns.IsCompanionLoadable(name)\n    if name == "EasyFind_GPS" or name == "EasyFind_Questie" then return true end\n', 1),
    ("EasyFind", "Core/Extensions.lua", "local function Installed(addon) return C_AddOns.DoesAddOnExist(addon) and not OldCopy(addon) end",
     'local function Installed(addon) return addon == "EasyFind_GPS" or addon == "EasyFind_Questie" '
     "or (C_AddOns.DoesAddOnExist(addon) and not OldCopy(addon)) end", 1),
] + TAINT_EDITS

# Its own table, not EasyFind's: it has an L of its own, among others.
QUESTIE_HEADER = ("local _, ns = ...", "local _, shared = ...\nlocal ns = shared.QuestieExtension")
QUESTIE_NAMESPACE = """-- Generated by tools/assemble.py. The Questie extension was an addon with a private
-- table. In one addon every file shares one, so it keeps a table of its own inside it.
local _, shared = ...
shared.QuestieExtension = {}
"""


def allowed_on_forever(rules: str) -> bool:
    for kind, value in RULE.findall(rules):
        if kind == "AllowLoadGameType" and "camelot" not in value:
            return False
    return True


def toc_entries(text: str) -> list[tuple[str, str]]:
    """(file, rules) for each file line."""
    out = []
    for line in text.replace("\r", "").split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = re.match(r"^(.*?)\s+(\[.*\])$", stripped)
        file, rules = (match.group(1), match.group(2)) if match else (stripped, "")
        out.append((file.replace("\\", "/"), rules))
    return out


def metadata(text: str) -> dict[str, str]:
    return dict(re.findall(r"^##\s*([\w-]+):\s*(.*?)\s*$", text.replace("\r", ""), re.M))


def locale_only(rules: str) -> str:
    """The rules a line keeps: only Forever's lines are left, so a game type says nothing."""
    return " ".join(f"[{kind} {value}]" for kind, value in RULE.findall(rules) if kind != "AllowLoadGameType")


def rewrite_paths(text: str) -> str:
    return PATHS.sub(lambda m: f"Interface{m[1]}AddOns{m[1]}ForeverGPS{m[1]}Vendor{m[1]}{m[2]}{m[1]}", text)


class Assembly:
    def __init__(self) -> None:
        self.files: dict[str, object] = {}     # path in the folder -> bytes, or a Path to copy as it is
        self.problems: list[str] = []
        self.applied: dict[tuple, int] = {}
        self.versions: dict[str, str] = {}

    def vendor(self, addon: str) -> list[str]:
        base = ADDONS / addon
        toc = (base / f"{addon}.toc").read_text(encoding="utf-8")
        version = metadata(toc).get("Version", "?")
        self.versions[addon] = version
        lines: list[str] = []
        listed = set()
        for file, rules in toc_entries(toc):
            if not allowed_on_forever(rules) or file in LEFT_OUT.get(addon, ()):
                continue
            path = base / file
            if not path.exists():
                self.problems.append(f"{addon}: its TOC lists missing {file}")
                continue
            listed.add(file)
            kept = locale_only(rules)
            lines.append(f"Vendor/{addon}/{file}" + (f" {kept}" if kept else ""))
            self.add_source(addon, file, path, version)
        skip = EXCLUDED_PREFIXES.get(addon, ())
        for path in sorted(base.rglob("*")):
            rel = path.relative_to(base).as_posix()
            if path.is_file() and path.suffix.lower() in ASSET_SUFFIXES and not rel.startswith(skip):
                self.files[f"Vendor/{addon}/{rel}"] = path
        for name in LICENSE_FILES:
            self.files[f"Vendor/{addon}/{name}"] = base / name
        return lines

    def add_source(self, addon: str, file: str, path: Path, version: str) -> None:
        text = path.read_bytes().decode("utf-8")
        for edit in EDITS:
            if edit[0] == addon and edit[1] == file:
                old, new, want = edit[2], edit[3].replace("{version}", version), edit[4]
                self.applied[edit[:3]] = text.count(old)
                if text.count(old) != want:
                    self.problems.append(f"{addon}/{file}: expected {want} of {old!r}, found {text.count(old)}")
                text = text.replace(old, new)
        if addon == "EasyFind_Questie" and QUESTIE_HEADER[0] in text:
            text = text.replace(QUESTIE_HEADER[0], QUESTIE_HEADER[1], 1)
        self.files[f"Vendor/{addon}/{file}"] = rewrite_paths(text).encode("utf-8")

    def own(self) -> list[str]:
        base = ADDONS / "ForeverGPS"
        toc = (base / "ForeverGPS.toc").read_text(encoding="utf-8")
        lines = []
        for file, rules in toc_entries(toc):
            lines.append(file + (f" {rules}" if rules else ""))
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.name != "ForeverGPS.toc":
                self.files[path.relative_to(base).as_posix()] = path
        return lines

    def manifest(self) -> bytes:
        rows = "".join(f'    {{ name = "{a}", version = "{self.versions[a]}" }},\n' for a in VENDORS)
        return ("-- Generated by tools/assemble.py: what is under Vendor/, for reports.\n"
                f"ForeverGPS.VENDOR = {{\n{rows}}}\n").encode("utf-8")

    def toc(self, vendor_lines: list[str], own_lines: list[str]) -> bytes:
        text = (ADDONS / "ForeverGPS" / "ForeverGPS.toc").read_text(encoding="utf-8").replace("\r", "")
        head = [line for line in text.split("\n") if line.startswith("##")]
        # Preflight runs before anything: it is first to hear the saved variables.
        first = [line for line in own_lines if line.startswith("Core/Preflight.lua")]
        rest = [line for line in own_lines if not line.startswith("Core/Preflight.lua")]
        namespace = [line for line in rest if line.startswith("Core/Namespace.lua")]
        rest = [line for line in rest if not line.startswith("Core/Namespace.lua")]
        body = first + vendor_lines + namespace + ["Core/Vendor.lua"] + rest
        return ("\n".join(head) + "\n\n" + "\n".join(body) + "\n").encode("utf-8")

    def verify(self) -> None:
        for edit in EDITS:
            if edit[:3] not in self.applied:
                self.problems.append(f"{edit[0]}/{edit[1]}: declared edit never ran")
        toc = self.files["ForeverGPS.toc"]
        if b"\r" in toc:
            self.problems.append("the merged TOC has a carriage return")
        for file, _ in toc_entries(toc.decode("utf-8")):
            if file not in self.files:
                self.problems.append(f"the merged TOC lists missing {file}")
        names = [file for file, _ in toc_entries(toc.decode("utf-8"))]
        if len(names) != len(set(names)):
            self.problems.append("the merged TOC lists a file twice")
        for key, value in self.files.items():
            if key.endswith(".lua") and isinstance(value, bytes):
                for bad in PATHS.finditer(value.decode("utf-8")):
                    self.problems.append(f"{key}: a path escaped: {bad.group(0)}")


def build() -> Assembly:
    a = Assembly()
    lines: list[str] = []
    for addon in VENDORS:
        if addon == "EasyFind_Questie":
            a.files["Vendor/EasyFind_Questie/Namespace.lua"] = QUESTIE_NAMESPACE.encode("utf-8")
            lines.append("Vendor/EasyFind_Questie/Namespace.lua")
        lines.extend(a.vendor(addon))
    own = a.own()
    a.files["Core/Vendor.lua"] = a.manifest()
    a.files["ForeverGPS.toc"] = a.toc(lines, own)
    a.verify()
    return a


def write(a: Assembly) -> tuple[int, int]:
    """Writes what changed, removes what no longer belongs. Returns (written, total)."""
    written = 0
    for key, value in a.files.items():
        target = OUT / key
        data = value if isinstance(value, bytes) else None
        if data is None:
            source: Path = value  # type: ignore[assignment]
            if target.exists() and target.stat().st_size == source.stat().st_size \
                    and target.stat().st_mtime >= source.stat().st_mtime:
                continue
            data = source.read_bytes()
        elif target.exists() and target.read_bytes() == data:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        written += 1
    keep = {(OUT / key).resolve() for key in a.files}
    for path in sorted(OUT.rglob("*"), reverse=True):
        if path.is_file() and path.resolve() not in keep:
            path.unlink()
        elif path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    return written, len(a.files)


def main(argv: list[str]) -> int:
    assembly = build()
    if assembly.problems:
        for problem in assembly.problems:
            print("FAIL", problem)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    written, total = write(assembly)
    if "--quiet" not in argv:
        size = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
        print(f"{OUT.relative_to(ROOT).as_posix()}: {total} files ({written} updated), {size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
