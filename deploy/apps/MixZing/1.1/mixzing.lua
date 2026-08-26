-- ============================================================================
-- WADAMESH MUSIC PLAYER
-- ============================================================================
-- SDK 1.7 / wada.audio / wada.sd
--
-- MUSIC SOURCE:
--     SD:/Music/
--
-- Supported:
--     MP3
--     WAV
--
-- HOME:
--     MUSIC
--     FAVORITES
--
-- MUSIC:
--     Lists ONLY files directly inside /Music
--
-- PLAYER:
--     Previous
--     Play / Pause / Resume
--     Stop
--     Next
--     Favorite
--
-- FAVORITES:
--     Stored in favorites.json in the app's own storage.
--
-- SD:
--     wada.sd.list("/Music")
--
-- AUDIO:
--     wada.audio.play("sd:/Music/file.mp3")
--     wada.audio.pause()
--     wada.audio.resume()
--     wada.audio.stop()
--     wada.audio.status()
--
-- IMPORTANT:
--     No wada.fs.list() is used.
--     No invented SD API is used.
--     No recursive SD scan is performed.
-- ============================================================================


local ui = wada.ui
local sys = wada.sys
local audio = wada.audio
local fs = wada.fs

local C = ui.colors

local app = {}


-- ============================================================================
-- DISPLAY
-- ============================================================================

local W = 300
local H = 400


-- ============================================================================
-- FILES
-- ============================================================================

local FAVORITES_FILE = "favorites.json"

local MUSIC_DIR = "/Music"


-- ============================================================================
-- SCREEN NAMES
-- ============================================================================

local SCREEN_HOME      = "home"
local SCREEN_MUSIC     = "music"
local SCREEN_FAVORITES = "favorites"
local SCREEN_PLAYER    = "player"


-- ============================================================================
-- UTF-8 ICONS
--
-- These are deliberately created from UTF-8 bytes rather than relying on
-- a graphical icon system which is not currently exposed to Lua.
--
-- ============================================================================

local ICON_MUSIC =
    string.char(0xEF, 0x80, 0x81)       -- fa-music

local ICON_PLAY =
    string.char(0xEF, 0x81, 0x8B)       -- fa-play

local ICON_PAUSE =
    string.char(0xEF, 0x81, 0x8C)       -- fa-pause

local ICON_STOP =
    string.char(0xEF, 0x81, 0x8D)       -- fa-stop

local ICON_PREV =
    string.char(0xEF, 0x81, 0x88)       -- fa-step-backward

local ICON_NEXT =
    string.char(0xEF, 0x81, 0x89)       -- fa-step-forward

local ICON_STAR =
    string.char(0xEF, 0x80, 0x85)       -- fa-star

local ICON_STAR_EMPTY =
    string.char(0xEF, 0x98, 0xB3)       -- fa-star-o

local ICON_HOME =
    string.char(0xEF, 0x80, 0x95)       -- fa-home

local ICON_BACK =
    string.char(0xEF, 0x81, 0x90)       -- fa-arrow-left

local ICON_FOLDER =
    string.char(0xEF, 0x81, 0xBB)       -- fa-folder

local ICON_SD =
    string.char(0xEF, 0x8A, 0x87)       -- fa-hdd-o / storage-like


-- ============================================================================
-- STATE
-- ============================================================================

local screen = SCREEN_HOME

local favorites = {}

local music_playlist = {}
local current_playlist = nil
local current_playlist_name = "Music"

local selected_index = 0
local playing_index = 0

local selected_track = nil
local playing_track = nil

local player_state = "stopped"

local previous_screen = SCREEN_HOME

local music_loaded = false


-- ============================================================================
-- UI OBJECTS
-- ============================================================================

local title_line = nil
local subtitle_line = nil
local status_line = nil
local state_line = nil
local track_line = nil
local path_line = nil

local list_buttons = {}


-- ============================================================================
-- GENERAL HELPERS
-- ============================================================================

local function safe_string(v)

    if v == nil then
        return ""
    end

    return tostring(v)

end


local function lower(v)

    if v == nil then
        return ""
    end

    return string.lower(tostring(v))

end


local function clear_buttons()

    list_buttons = {}

end


-- ============================================================================
-- FILE TYPE
-- ============================================================================

local function is_mp3(name)

    return lower(name):sub(-4) == ".mp3"

end


local function is_wav(name)

    return lower(name):sub(-4) == ".wav"

end


local function is_audio(name)

    return is_mp3(name) or is_wav(name)

end


-- ============================================================================
-- SD ENTRY HELPERS
-- ============================================================================

local function is_directory(entry)

    if not entry then
        return false
    end

    local typ =
        entry.type or
        entry.kind or
        ""

    typ = lower(typ)

    if typ == "dir" then
        return true
    end

    if typ == "directory" then
        return true
    end

    if entry.is_dir == true then
        return true
    end

    return false

end


local function entry_name(entry)

    if not entry then
        return "?"
    end

    return tostring(
        entry.name or
        entry.filename or
        entry.file_name or
        "?"
    )

end


-- ============================================================================
-- STATUS
-- ============================================================================

local function set_status(text, color)

    if not status_line then
        return
    end

    status_line:set(
        safe_string(text)
    )

    status_line:color(
        color or C.sub
    )

end


-- ============================================================================
-- HEADER
-- ============================================================================

local function header(title, subtitle)

    title_line = ui.label(
        title,
        8,
        5,
        16,
        C.accent
    )

    if subtitle then

        subtitle_line = ui.label(
            subtitle,
            8,
            27,
            11,
            C.sub
        )

        subtitle_line:width(W - 16)

    end

end


-- ============================================================================
-- FAVORITES
-- ============================================================================

local function find_favorite(path)

    for i, item in ipairs(favorites) do

        if item.path == path then
            return i
        end

    end

    return 0

end


local function is_favorite(path)

    return find_favorite(path) ~= 0

end


-- ============================================================================
-- JSON
-- ============================================================================

local function json_escape(value)

    local s = safe_string(value)

    s = string.gsub(
        s,
        "\\",
        "\\\\"
    )

    s = string.gsub(
        s,
        "\"",
        "\\\""
    )

    s = string.gsub(
        s,
        "\r",
        "\\r"
    )

    s = string.gsub(
        s,
        "\n",
        "\\n"
    )

    return s

end


local function json_unescape(value)

    local s = safe_string(value)

    s = string.gsub(
        s,
        "\\n",
        "\n"
    )

    s = string.gsub(
        s,
        "\\r",
        "\r"
    )

    s = string.gsub(
        s,
        "\\\"",
        "\""
    )

    s = string.gsub(
        s,
        "\\\\",
        "\\"
    )

    return s

end


-- ============================================================================
-- ENCODE FAVORITES
-- ============================================================================

local function encode_favorites()

    local out =
        "{\n" ..
        "  \"favorites\": [\n"

    for i, item in ipairs(favorites) do

        out =
            out ..
            "    \"" ..
            json_escape(item.path) ..
            "\""

        if i < #favorites then
            out = out .. ","
        end

        out = out .. "\n"

    end

    out =
        out ..
        "  ]\n" ..
        "}\n"

    return out

end


-- ============================================================================
-- LOAD FAVORITES
-- ============================================================================

local function load_favorites()

    favorites = {}

    if not fs then
        return
    end

    if not fs.read then
        return
    end

    local ok, data =
        pcall(
            fs.read,
            FAVORITES_FILE,
            0,
            65535
        )

    if not ok then
        return
    end

    if not data then
        return
    end

    local text =
        tostring(data)

    local array =
        text:match(
            "\"favorites\"%s*:%s*%[(.-)%]"
        )

    if not array then
        return
    end

    for value in
        array:gmatch(
            "\"((\\.|[^\"\\])*)\""
        )
    do

        local path =
            json_unescape(value)

        -- Only accept Music paths.
        --
        -- This also prevents an old favorites.json from introducing
        -- arbitrary files outside /Music.

        if path ~= "" then

            local lower_path =
                lower(path)

            if lower_path:sub(1, 9) == "sd:/music"
               and is_audio(path)
            then

                local name =
                    path:match(
                        "([^/]+)$"
                    ) or path

                favorites[#favorites + 1] = {
                    path = path,
                    name = name
                }

            end

        end

    end

end


-- ============================================================================
-- SAVE FAVORITES
-- ============================================================================

local function save_favorites()

    if not fs then

        set_status(
            "Storage unavailable",
            C.bad
        )

        return false

    end

    if not fs.write then

        set_status(
            "Storage write unavailable",
            C.bad
        )

        return false

    end

    local data =
        encode_favorites()

    local ok, result =
        pcall(
            fs.write,
            FAVORITES_FILE,
            data
        )

    if not ok then

        set_status(
            "Could not save Favorites",
            C.bad
        )

        return false

    end

    if result == false then

        set_status(
            "Could not save Favorites",
            C.bad
        )

        return false

    end

    return true

end


-- ============================================================================
-- ADD FAVORITE
-- ============================================================================

local function add_favorite(track)

    if not track then
        return
    end

    if not is_favorite(track.path) then

        favorites[#favorites + 1] = {
            path = track.path,
            name = track.name
        }

        if save_favorites() then

            set_status(
                ICON_STAR .. " Added to Favorites",
                C.good
            )

        end

    else

        set_status(
            ICON_STAR .. " Already in Favorites",
            C.accent
        )

    end

end


-- ============================================================================
-- REMOVE FAVORITE
-- ============================================================================

local function remove_favorite(path)

    local index =
        find_favorite(path)

    if index == 0 then
        return
    end

    table.remove(
        favorites,
        index
    )

    save_favorites()

    set_status(
        "Removed from Favorites",
        C.sub
    )

end


-- ============================================================================
-- READ MUSIC DIRECTORY
--
-- ONLY /Music is scanned.
-- No other directory is allowed.
-- ============================================================================

local function read_music_directory()

    if not wada.sd then

        return nil,
            "SD unavailable"

    end

    if not wada.sd.list then

        return nil,
            "SD directory listing unavailable"

    end

    local ok, result =
        pcall(
            wada.sd.list,
            MUSIC_DIR
        )

    if not ok then

        return nil,
            tostring(result)

    end

    if not result then

        return nil,
            "Music directory unavailable"

    end

    return result

end


-- ============================================================================
-- BUILD MUSIC PLAYLIST
-- ============================================================================

local function load_music()

    music_playlist = {}
    music_loaded = false

    local entries, err =
        read_music_directory()

    if not entries then

        set_status(
            err,
            C.bad
        )

        return false

    end

    for _, entry in ipairs(entries) do

        -- Ignore directories.
        if not is_directory(entry) then

            local name =
                entry_name(entry)

            if is_audio(name) then

                local path =
                    "sd:/Music/" .. name

                music_playlist[#music_playlist + 1] = {
                    name = name,
                    path = path,
                    source = "SD",
                    type =
                        is_mp3(name)
                        and "MP3"
                        or "WAV"
                }

            end

        end

    end

    table.sort(
        music_playlist,
        function(a, b)

            return lower(a.name)
                < lower(b.name)

        end
    )

    music_loaded = true

    return true

end


-- ============================================================================
-- BUILD FAVORITES PLAYLIST
-- ============================================================================

local function build_favorite_playlist()

    local playlist = {}

    for _, item in ipairs(favorites) do

        -- Only Music directory is allowed.
        if lower(item.path):sub(1, 9)
            == "sd:/music"
        then

            if is_audio(item.path) then

                playlist[#playlist + 1] = {
                    name =
                        item.name or
                        item.path:match(
                            "([^/]+)$"
                        ) or
                        item.path,

                    path = item.path,

                    source = "SD",

                    type =
                        is_mp3(item.name or item.path)
                        and "MP3"
                        or "WAV"
                }

            end

        end

    end

    return playlist

end


-- ============================================================================
-- STOP
-- ============================================================================

local function stop_audio()

    if audio and audio.stop then

        pcall(
            audio.stop
        )

    end

    player_state = "stopped"

    playing_track = nil
    playing_index = 0

end


-- ============================================================================
-- PLAY
-- ============================================================================

local function play_track(track, index)

    if not track then

        set_status(
            "No track selected",
            C.bad
        )

        return false

    end

    if not audio then

        set_status(
            "Audio API unavailable",
            C.bad
        )

        return false

    end

    if not audio.play then

        set_status(
            "Audio playback unavailable",
            C.bad
        )

        return false

    end

    -- Always stop the previous stream first.

    pcall(
        audio.stop
    )

    local ok, result =
        pcall(
            audio.play,
            track.path
        )

    if not ok then

        set_status(
            "Playback error: " ..
            safe_string(result),
            C.bad
        )

        player_state = "stopped"

        return false

    end

    if result == false then

        set_status(
            "Playback rejected",
            C.bad
        )

        player_state = "stopped"

        return false

    end

    selected_track =
        track

    selected_index =
        index or selected_index

    playing_track =
        track

    playing_index =
        index or selected_index

    player_state =
        "playing"

    set_status(
        ICON_PLAY ..
        " " ..
        track.name,
        C.good
    )

    return true

end


-- ============================================================================
-- NEXT
-- ============================================================================

local function next_track()

    if not current_playlist
       or #current_playlist == 0
    then

        set_status(
            "Playlist is empty",
            C.sub
        )

        return

    end

    local index =
        playing_index

    if index <= 0 then
        index = selected_index
    end

    index =
        index + 1

    if index > #current_playlist then
        index = 1
    end

    selected_index =
        index

    selected_track =
        current_playlist[index]

    play_track(
        selected_track,
        index
    )

end


-- ============================================================================
-- PREVIOUS
-- ============================================================================

local function previous_track()

    if not current_playlist
       or #current_playlist == 0
    then

        set_status(
            "Playlist is empty",
            C.sub
        )

        return

    end

    local index =
        playing_index

    if index <= 0 then
        index = selected_index
    end

    index =
        index - 1

    if index < 1 then
        index = #current_playlist
    end

    selected_index =
        index

    selected_track =
        current_playlist[index]

    play_track(
        selected_track,
        index
    )

end


-- ============================================================================
-- PAUSE / RESUME
-- ============================================================================

local function toggle_pause()

    if not audio then
        return
    end

    if player_state == "playing" then

        if not audio.pause then

            set_status(
                "Pause unavailable",
                C.bad
            )

            return

        end

        local ok, result =
            pcall(
                audio.pause
            )

        if ok and result ~= false then

            player_state =
                "paused"

            set_status(
                ICON_PAUSE .. " Paused",
                C.accent
            )

        else

            set_status(
                "Pause failed",
                C.bad
            )

        end

        return

    end

    if player_state == "paused" then

        if not audio.resume then

            set_status(
                "Resume unavailable",
                C.bad
            )

            return

        end

        local ok, result =
            pcall(
                audio.resume
            )

        if ok and result ~= false then

            player_state =
                "playing"

            set_status(
                ICON_PLAY .. " Playing",
                C.good
            )

        else

            set_status(
                "Resume failed",
                C.bad
            )

        end

        return

    end

    if selected_track then

        play_track(
            selected_track,
            selected_index
        )

    end

end


-- ============================================================================
-- AUDIO STATUS
-- ============================================================================

local function update_audio_state()

    if not audio
       or not audio.status
    then
        return
    end

    local ok, result =
        pcall(
            audio.status
        )

    if not ok then
        return
    end

    if type(result) ~= "table" then
        return
    end

    if result.state then

        player_state =
            tostring(
                result.state
            )

    end

end


-- ============================================================================
-- HOME
-- ============================================================================

local function show_home()

    screen =
        SCREEN_HOME

    clear_buttons()

    ui.scroll(true)

    header(
        ICON_MUSIC .. "  MUSIC",
        "WADAMESH AUDIO PLAYER"
    )

    -- Large central music symbol.

    ui.label(
        ICON_MUSIC,
        126,
        65,
        42,
        C.accent
    )

    -- MUSIC

    ui.button(
        ICON_MUSIC .. "  MUSIC",
        18,
        125,
        W - 36,
        44,
        function()

            current_playlist =
                music_playlist

            current_playlist_name =
                "Music"

            previous_screen =
                SCREEN_HOME

            show_music()

        end
    )

    -- FAVORITES

    ui.button(
        ICON_STAR .. "  FAVORITES",
        18,
        180,
        W - 36,
        44,
        function()

            current_playlist =
                build_favorite_playlist()

            current_playlist_name =
                "Favorites"

            previous_screen =
                SCREEN_HOME

            show_favorites()

        end
    )

    -- Status

    local count =
        #music_playlist

    ui.label(
        tostring(count) ..
        " music files in /Music",
        18,
        255,
        11,
        C.sub
    )

    ui.label(
        tostring(#favorites) ..
        " favorite tracks",
        18,
        276,
        11,
        C.sub
    )

    -- Current playback information.

    if playing_track then

        ui.label(
            ICON_PLAY ..
            " " ..
            playing_track.name,
            18,
            315,
            10,
            C.good
        )

    else

        ui.label(
            "Nothing playing",
            18,
            315,
            10,
            C.sub
        )

    end

end


-- ============================================================================
-- MUSIC SCREEN
-- ============================================================================

function show_music()

    screen =
        SCREEN_MUSIC

    clear_buttons()

    ui.scroll(true)

    header(
        ICON_MUSIC .. "  MUSIC",
        "/Music"
    )

    -- Back

    ui.button(
        ICON_BACK .. "  HOME",
        8,
        50,
        92,
        28,
        function()

            show_home()

        end
    )

    -- Refresh

    ui.button(
        "↻  REFRESH",
        108,
        50,
        92,
        28,
        function()

            load_music()

            current_playlist =
                music_playlist

            set_status(
                tostring(#music_playlist) ..
                " tracks found",
                C.good
            )

            show_music()

        end
    )

    status_line =
        ui.label(
            tostring(#music_playlist) ..
            " tracks",
            210,
            58,
            9,
            C.sub
        )

    status_line:width(
        W - 218
    )

    local y = 88

    if not music_loaded then

        load_music()

    end

    if #music_playlist == 0 then

        ui.label(
            "No MP3 or WAV files found.",
            8,
            y,
            12,
            C.sub
        )

        ui.label(
            "Place music directly in /Music.",
            8,
            y + 24,
            10,
            C.sub
        )

        return

    end

    --------------------------------------------------------------------------
    -- Every item is a real button.
    --
    -- ui.scroll(true) allows the list to extend below the physical display.
    --------------------------------------------------------------------------

    for i, track in ipairs(music_playlist) do

        local index =
            i

        local marker =
            is_favorite(track.path)
            and ICON_STAR
            or ICON_MUSIC

        local text =
            marker ..
            "  " ..
            track.name

        local b =
            ui.button(
                text,
                8,
                y,
                W - 16,
                31,
                function()

                    current_playlist =
                        music_playlist

                    current_playlist_name =
                        "Music"

                    selected_index =
                        index

                    selected_track =
                        track

                    previous_screen =
                        SCREEN_MUSIC

                    show_player()

                end
            )

        list_buttons[#list_buttons + 1] =
            b

        y = y + 35

    end

end


-- ============================================================================
-- FAVORITES SCREEN
-- ============================================================================

function show_favorites()

    screen =
        SCREEN_FAVORITES

    clear_buttons()

    ui.scroll(true)

    header(
        ICON_STAR .. "  FAVORITES",
        tostring(#favorites) ..
        " saved tracks"
    )

    ui.button(
        ICON_BACK .. "  HOME",
        8,
        50,
        92,
        28,
        function()

            show_home()

        end
    )

    local y = 88

    current_playlist =
        build_favorite_playlist()

    if #current_playlist == 0 then

        ui.label(
            "No favorite tracks.",
            8,
            y,
            12,
            C.sub
        )

        ui.label(
            "Add songs with the star button.",
            8,
            y + 24,
            10,
            C.sub
        )

        return

    end

    for i, track in ipairs(current_playlist) do

        local index =
            i

        local b =
            ui.button(
                ICON_STAR ..
                "  " ..
                track.name,
                8,
                y,
                W - 16,
                31,
                function()

                    current_playlist =
                        build_favorite_playlist()

                    current_playlist_name =
                        "Favorites"

                    selected_index =
                        index

                    selected_track =
                        current_playlist[index]

                    previous_screen =
                        SCREEN_FAVORITES

                    show_player()

                end
            )

        list_buttons[#list_buttons + 1] =
            b

        y = y + 35

    end

end


-- ============================================================================
-- PLAYER
-- ============================================================================

function show_player()

    screen =
        SCREEN_PLAYER

    clear_buttons()

    ui.scroll(true)

    header(
        ICON_MUSIC .. "  NOW PLAYING",
        current_playlist_name
    )

    --------------------------------------------------------------------------
    -- Music symbol
    --------------------------------------------------------------------------

    ui.label(
        ICON_MUSIC,
        127,
        54,
        40,
        C.accent
    )

    --------------------------------------------------------------------------
    -- Track information
    --------------------------------------------------------------------------

    if selected_track then

        track_line =
            ui.label(
                selected_track.name,
                10,
                102,
                15,
                C.text
            )

        track_line:width(
            W - 20
        )

        local info =
            selected_track.type ..
            "  •  " ..
            selected_track.source

        subtitle_line =
            ui.label(
                info,
                10,
                127,
                10,
                C.sub
            )

        subtitle_line:width(
            W - 20
        )

        path_line =
            ui.label(
                selected_track.path,
                10,
                146,
                9,
                C.sub
            )

        path_line:width(
            W - 20
        )

    end

    --------------------------------------------------------------------------
    -- State
    --------------------------------------------------------------------------

    local state_text =
        "STOPPED"

    local state_color =
        C.sub

    if player_state == "playing" then

        state_text =
            "PLAYING"

        state_color =
            C.good

    elseif player_state == "paused" then

        state_text =
            "PAUSED"

        state_color =
            C.accent

    end

    state_line =
        ui.label(
            state_text,
            10,
            173,
            11,
            state_color
        )

    --------------------------------------------------------------------------
    -- PREVIOUS
    --------------------------------------------------------------------------

    ui.button(
        ICON_PREV,
        8,
        208,
        86,
        44,
        function()

            previous_track()

            show_player()

        end
    )

    --------------------------------------------------------------------------
    -- PLAY / PAUSE
    --------------------------------------------------------------------------

    local center_text

    if player_state == "playing" then

        center_text =
            ICON_PAUSE

    else

        center_text =
            ICON_PLAY

    end

    ui.button(
        center_text,
        101,
        208,
        98,
        44,
        function()

            toggle_pause()

            show_player()

        end
    )

    --------------------------------------------------------------------------
    -- NEXT
    --------------------------------------------------------------------------

    ui.button(
        ICON_NEXT,
        206,
        208,
        86,
        44,
        function()

            next_track()

            show_player()

        end
    )

    --------------------------------------------------------------------------
    -- STOP
    --------------------------------------------------------------------------

    ui.button(
        ICON_STOP .. "  STOP",
        8,
        262,
        W - 16,
        34,
        function()

            stop_audio()

            set_status(
                "Playback stopped",
                C.good
            )

            show_player()

        end
    )

    --------------------------------------------------------------------------
    -- FAVORITE
    --------------------------------------------------------------------------

    local favorite_label

    if selected_track
       and is_favorite(
           selected_track.path
       )
    then

        favorite_label =
            ICON_STAR ..
            "  REMOVE FAVORITE"

    else

        favorite_label =
            ICON_STAR_EMPTY ..
            "  ADD TO FAVORITES"

    end

    ui.button(
        favorite_label,
        8,
        306,
        W - 16,
        34,
        function()

            if not selected_track then
                return
            end

            if is_favorite(
                selected_track.path
            )
            then

                remove_favorite(
                    selected_track.path
                )

            else

                add_favorite(
                    selected_track
                )

            end

            show_player()

        end
    )

    --------------------------------------------------------------------------
    -- BACK
    --------------------------------------------------------------------------

    ui.button(
        ICON_BACK .. "  BACK",
        8,
        350,
        W - 16,
        30,
        function()

            if previous_screen ==
                SCREEN_FAVORITES
            then

                show_favorites()

            else

                show_music()

            end

        end
    )

end


-- ============================================================================
-- OPEN
-- ============================================================================

function app.on_open(w, h)

    W =
        w or 300

    H =
        h or 400

    --------------------------------------------------------------------------
    -- Runtime reset
    --------------------------------------------------------------------------

    screen =
        SCREEN_HOME

    selected_index =
        0

    playing_index =
        0

    selected_track =
        nil

    playing_track =
        nil

    player_state =
        "stopped"

    previous_screen =
        SCREEN_HOME

    music_playlist =
        {}

    current_playlist =
        nil

    current_playlist_name =
        "Music"

    music_loaded =
        false

    --------------------------------------------------------------------------
    -- Load favorites first.
    --------------------------------------------------------------------------

    load_favorites()

    --------------------------------------------------------------------------
    -- Capability check.
    --
    -- Do not call audio here.
    -- Opening the app must not start playback.
    --------------------------------------------------------------------------

    local caps = nil

    local caps_ok, caps_result =
        pcall(
            sys.caps
        )

    if caps_ok then
        caps = caps_result
    end

    if not caps then

        ui.label(
            ICON_MUSIC ..
            "  MUSIC PLAYER",
            8,
            8,
            16,
            C.accent
        )

        ui.label(
            "Capabilities unavailable.",
            8,
            45,
            12,
            C.bad
        )

        return

    end

    if not caps.sd then

        ui.label(
            ICON_MUSIC ..
            "  MUSIC PLAYER",
            8,
            8,
            16,
            C.accent
        )

        ui.label(
            "SD card unavailable.",
            8,
            45,
            12,
            C.bad
        )

        return

    end

    if not caps.audio or not audio then

        ui.label(
            ICON_MUSIC ..
            "  MUSIC PLAYER",
            8,
            8,
            16,
            C.accent
        )

        ui.label(
            "Audio playback unavailable.",
            8,
            45,
            12,
            C.bad
        )

        return

    end

    --------------------------------------------------------------------------
    -- Load ONLY /Music.
    --------------------------------------------------------------------------

    load_music()

    current_playlist =
        music_playlist

    current_playlist_name =
        "Music"

    --------------------------------------------------------------------------
    -- HOME
    --------------------------------------------------------------------------

    show_home()

end


-- ============================================================================
-- CLOSE
-- ============================================================================

function app.on_close()

    if audio
       and audio.stop
    then

        pcall(
            audio.stop
        )

    end

    selected_track =
        nil

    playing_track =
        nil

    current_playlist =
        nil

    player_state =
        "stopped"

end


-- ============================================================================
-- INPUT
-- ============================================================================

function app.on_input(ev)

    -- No undocumented keyboard API is used.
    -- ui.button() handles touch/button interaction.

end


-- ============================================================================
-- RETURN APP
-- ============================================================================

return app
