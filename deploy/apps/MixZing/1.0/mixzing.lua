-- WADAMESH MUSIC PLAYER
-- SDK 1.7 / audio playback
--
-- HOME
--   MUSIC
--   FOLDERS
--   FAVORITES
--
-- MUSIC
--   App-owned music playlist
--
-- FOLDERS
--   SD Card browser
--
-- PLAYER
--   Previous
--   Play / Pause / Resume
--   Stop
--   Next
--   Favorite
--
-- FAVORITES
--   Stored in favorites.json
--
-- Audio API:
--   wada.audio.play()
--   wada.audio.pause()
--   wada.audio.resume()
--   wada.audio.stop()
--   wada.audio.status()
--
-- SD paths:
--   sd:/folder/file.mp3
--
-- App-storage paths:
--   file.mp3
--
-- IMPORTANT:
-- The current SDK does NOT expose a general app-storage
-- directory browser. Therefore app-storage music is represented
-- by an app-owned playlist rather than inventing wada.fs.list().


local ui = wada.ui
local sys = wada.sys
local audio = wada.audio
local fs = wada.fs

local C = ui.colors

local app = {}

------------------------------------------------------------
-- DISPLAY
------------------------------------------------------------

local W = 300
local H = 400

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------

local FAVORITES_FILE = "favorites.json"

local SOURCE_APP = "app"
local SOURCE_SD = "sd"

local SCREEN_HOME = "home"
local SCREEN_MUSIC = "music"
local SCREEN_FOLDERS = "folders"
local SCREEN_FAVORITES = "favorites"
local SCREEN_PLAYER = "player"

------------------------------------------------------------
-- APP STORAGE PLAYLIST
--
-- These are files installed together with the Lua app.
--
-- IMPORTANT:
-- #316 app audio accepts only a safe flat filename.
------------------------------------------------------------

local APP_TRACKS = {
    {
        name = "music1.mp3",
        path = "music1.mp3",
        source = SOURCE_APP,
        type = "MP3"
    },

    {
        name = "music2.mp3",
        path = "music2.mp3",
        source = SOURCE_APP,
        type = "MP3"
    },

    {
        name = "music3.mp3",
        path = "music3.mp3",
        source = SOURCE_APP,
        type = "MP3"
    }
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local screen = SCREEN_HOME

local current_sd_path = "/"

local music_playlist = {}
local current_playlist = nil
local current_playlist_name = "Music"

local selected_index = 0
local playing_index = 0

local selected_track = nil
local playing_track = nil

local player_state = "stopped"

local previous_screen = SCREEN_HOME

------------------------------------------------------------
-- FAVORITES
------------------------------------------------------------

local favorites = {}

------------------------------------------------------------
-- UI
------------------------------------------------------------

local status_line = nil
local state_line = nil
local title_line = nil
local subtitle_line = nil
local track_line = nil
local path_line = nil

local list_buttons = {}

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function clear_buttons()

    list_buttons = {}

end

------------------------------------------------------------

local function safe_string(v)

    if v == nil then
        return ""
    end

    return tostring(v)

end

------------------------------------------------------------

local function lower(v)

    if v == nil then
        return ""
    end

    return string.lower(
        tostring(v)
    )

end

------------------------------------------------------------

local function is_mp3(name)

    return lower(name):sub(-4) == ".mp3"

end

------------------------------------------------------------

local function is_wav(name)

    return lower(name):sub(-4) == ".wav"

end

------------------------------------------------------------

local function is_audio(name)

    return is_mp3(name)
        or is_wav(name)

end

------------------------------------------------------------

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

------------------------------------------------------------

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

------------------------------------------------------------

local function join_path(base, name)

    if base == "/" then

        return "/" .. name

    end

    if base:sub(-1) == "/" then

        return base .. name

    end

    return base .. "/" .. name

end

------------------------------------------------------------

local function parent_path(path)

    if path == "/" then
        return "/"
    end

    local p =
        path:match(
            "^(.*)/[^/]+/?$"
        )

    if not p or p == "" then
        return "/"
    end

    return p

end

------------------------------------------------------------
-- STATUS
------------------------------------------------------------

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

------------------------------------------------------------
-- HEADER
------------------------------------------------------------

local function header(title, subtitle)

    title_line =
        ui.label(
            title,
            8,
            5,
            16,
            C.accent
        )

    if subtitle then

        subtitle_line =
            ui.label(
                subtitle,
                8,
                27,
                11,
                C.sub
            )

        subtitle_line:width(
            W - 16
        )

    end

end

------------------------------------------------------------
-- FAVORITE SEARCH
------------------------------------------------------------

local function find_favorite(path)

    for i, item in ipairs(favorites) do

        if item.path == path then
            return i
        end

    end

    return 0

end

------------------------------------------------------------

local function is_favorite(path)

    return find_favorite(path) ~= 0

end

------------------------------------------------------------
-- JSON ESCAPE
------------------------------------------------------------

local function json_escape(value)

    local s =
        safe_string(value)

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

------------------------------------------------------------
-- JSON UNESCAPE
------------------------------------------------------------

local function json_unescape(value)

    local s =
        safe_string(value)

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

------------------------------------------------------------
-- ENCODE FAVORITES
------------------------------------------------------------

local function encode_favorites()

    local out =
        "{\n" ..
        "  \"favorites\": [\n"

    for i, item in ipairs(favorites) do

        out =
            out ..
            "    \"" ..
            json_escape(
                item.path
            ) ..
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

------------------------------------------------------------
-- LOAD FAVORITES
------------------------------------------------------------

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

    --------------------------------------------------------
    -- Only parse strings inside the favorites array.
    --------------------------------------------------------

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

        if path ~= "" then

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

------------------------------------------------------------
-- SAVE FAVORITES
------------------------------------------------------------

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

------------------------------------------------------------
-- ADD FAVORITE
------------------------------------------------------------

local function add_favorite(track)

    if not track then
        return
    end

    if is_favorite(track.path) then

        set_status(
            "Already in Favorites",
            C.accent
        )

        return

    end

    favorites[#favorites + 1] = {
        path = track.path,
        name = track.name
    }

    if save_favorites() then

        set_status(
            "Added to Favorites",
            C.good
        )

    end

end

------------------------------------------------------------
-- REMOVE FAVORITE
------------------------------------------------------------

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

------------------------------------------------------------
-- CREATE FAVORITE PLAYLIST
------------------------------------------------------------

local function build_favorite_playlist()

    local playlist = {}

    for _, item in ipairs(favorites) do

        local name =
            item.name or
            item.path

        playlist[#playlist + 1] = {
            name = name,
            path = item.path,
            source =
                item.path:sub(1, 3)
                    == "sd:"
                and SOURCE_SD
                or SOURCE_APP,
            type =
                is_mp3(name)
                and "MP3"
                or "WAV"
        }

    end

    return playlist

end

------------------------------------------------------------
-- STOP
------------------------------------------------------------

local function stop_audio()

    if not audio then

        player_state =
            "stopped"

        playing_track = nil
        playing_index = 0

        return false

    end

    local ok, result =
        pcall(
            audio.stop
        )

    player_state =
        "stopped"

    playing_track = nil
    playing_index = 0

    return ok and result ~= false

end

------------------------------------------------------------
-- PLAY
------------------------------------------------------------

local function play_track(
    track,
    index
)

    if not track then

        set_status(
            "No track selected",
            C.bad
        )

        return false

    end

    if not audio or
       not audio.play
    then

        set_status(
            "Audio API unavailable",
            C.bad
        )

        return false

    end

    --------------------------------------------------------
    -- Stop previous track.
    --------------------------------------------------------

    pcall(
        audio.stop
    )

    --------------------------------------------------------
    -- #316:
    --
    -- App storage:
    --     "file.mp3"
    --
    -- SD:
    --     "sd:/Music/file.mp3"
    --------------------------------------------------------

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

        return false

    end

    if result == false then

        set_status(
            "Playback rejected",
            C.bad
        )

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
        "Playing: " ..
        track.name,
        C.good
    )

    return true

end

------------------------------------------------------------
-- NEXT
------------------------------------------------------------

local function next_track()

    if not current_playlist or
       #current_playlist == 0
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

        index =
            selected_index

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

------------------------------------------------------------
-- PREVIOUS
------------------------------------------------------------

local function previous_track()

    if not current_playlist or
       #current_playlist == 0
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

        index =
            selected_index

    end

    index =
        index - 1

    if index < 1 then

        index =
            #current_playlist

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

------------------------------------------------------------
-- PAUSE / RESUME
------------------------------------------------------------

local function toggle_pause()

    if not audio then
        return
    end

    if player_state == "playing" then

        local ok, result =
            pcall(
                audio.pause
            )

        if ok and result ~= false then

            player_state =
                "paused"

            set_status(
                "Paused",
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

        local ok, result =
            pcall(
                audio.resume
            )

        if ok and result ~= false then

            player_state =
                "playing"

            set_status(
                "Playing",
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

------------------------------------------------------------
-- AUDIO STATUS
------------------------------------------------------------

local function update_audio_state()

    if not audio or
       not audio.status
    then
        return
    end

    local ok, result =
        pcall(
            audio.status
        )

    if not ok or
       type(result) ~= "table"
    then

        return

    end

    if result.state then

        player_state =
            tostring(
                result.state
            )

    end

end

------------------------------------------------------------
-- SD LIST
------------------------------------------------------------

local function read_sd(path)

    if not wada.sd then

        return nil,
            "SD unavailable"

    end

    if not wada.sd.list then

        return nil,
            "SD browser unavailable"

    end

    local ok, result =
        pcall(
            wada.sd.list,
            path
        )

    if not ok then

        return nil,
            tostring(result)

    end

    if not result then

        return nil,
            "Empty directory"

    end

    return result

end

------------------------------------------------------------
-- SORT SD
------------------------------------------------------------

local function sort_entries(entries)

    table.sort(
        entries,
        function(a, b)

            local ad =
                is_directory(a)

            local bd =
                is_directory(b)

            if ad ~= bd then

                return ad

            end

            return lower(
                entry_name(a)
            ) <
            lower(
                entry_name(b)
            )

        end
    )

end

------------------------------------------------------------
-- LOAD SD DIRECTORY
------------------------------------------------------------

local function load_sd_directory(path)

    local result, err =
        read_sd(path)

    if not result then

        set_status(
            err,
            C.bad
        )

        return false

    end

    sort_entries(result)

    current_sd_path =
        path

    return true

end

------------------------------------------------------------
-- BUILD SD PLAYLIST
------------------------------------------------------------

local function build_sd_playlist()

    local result =
        read_sd(
            current_sd_path
        )

    if not result then
        return {}
    end

    local playlist = {}

    for _, entry in ipairs(result) do

        if not is_directory(entry) then

            local name =
                entry_name(entry)

            if is_audio(name) then

                playlist[#playlist + 1] = {
                    name = name,
                    path =
                        "sd:" ..
                        join_path(
                            current_sd_path,
                            name
                        ),
                    source = SOURCE_SD,
                    type =
                        is_mp3(name)
                        and "MP3"
                        or "WAV"
                }

            end

        end

    end

    table.sort(
        playlist,
        function(a, b)

            return lower(a.name)
                < lower(b.name)

        end
    )

    return playlist

end

------------------------------------------------------------
-- HOME
------------------------------------------------------------

local function show_home()

    screen =
        SCREEN_HOME

    clear_buttons()

    ui.scroll(true)

    header(
        "MUSIC",
        "WADAMESH AUDIO PLAYER"
    )

    ui.label(
        "♫",
        125,
        58,
        45,
        C.accent
    )

    ui.button(
        "MUSIC",
        18,
        125,
        W - 36,
        42,
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

    ui.button(
        "FOLDERS",
        18,
        175,
        W - 36,
        42,
        function()

            previous_screen =
                SCREEN_HOME

            show_folders()

        end
    )

    ui.button(
        "★  FAVORITES",
        18,
        225,
        W - 36,
        42,
        function()

            previous_screen =
                SCREEN_HOME

            show_favorites()

        end
    )

    ui.label(
        tostring(#favorites) ..
        " favorite tracks",
        18,
        292,
        11,
        C.sub
    )

end

------------------------------------------------------------
-- MUSIC
------------------------------------------------------------

function show_music()

    screen =
        SCREEN_MUSIC

    clear_buttons()

    ui.scroll(true)

    header(
        "MUSIC",
        "App storage"
    )

    ui.button(
        "‹  HOME",
        8,
        50,
        90,
        28,
        function()

            show_home()

        end
    )

    local y = 88

    if #music_playlist == 0 then

        ui.label(
            "No music installed.",
            8,
            y,
            12,
            C.sub
        )

        return

    end

    local max =
        math.min(
            #music_playlist,
            8
        )

    for i = 1, max do

        local track =
            music_playlist[i]

        local index =
            i

        local marker =
            is_favorite(track.path)
            and "★"
            or "♫"

        local b =
            ui.button(
                marker ..
                "  " ..
                track.name,
                8,
                y,
                W - 16,
                30,
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

        y = y + 34

    end

end

------------------------------------------------------------
-- FOLDERS
------------------------------------------------------------

function show_folders()

    screen =
        SCREEN_FOLDERS

    clear_buttons()

    ui.scroll(true)

    header(
        "FOLDERS",
        "SD Card"
    )

    path_line =
        ui.label(
            "SD: " ..
            current_sd_path,
            8,
            50,
            10,
            C.accent
        )

    path_line:width(
        W - 16
    )

    local y = 74

    if current_sd_path ~= "/" then

        ui.button(
            "‹  BACK",
            8,
            y,
            W - 16,
            28,
            function()

                current_sd_path =
                    parent_path(
                        current_sd_path
                    )

                show_folders()

            end
        )

        y = y + 34

    else

        ui.button(
            "‹  HOME",
            8,
            y,
            W - 16,
            28,
            function()

                show_home()

            end
        )

        y = y + 34

    end

    local result =
        read_sd(
            current_sd_path
        )

    if not result then

        ui.label(
            "SD directory unavailable.",
            8,
            y,
            12,
            C.bad
        )

        return

    end

    sort_entries(result)

    local count = 0

    for _, entry in ipairs(result) do

        if count >= 7 then
            break
        end

        local item =
            entry

        local name =
            entry_name(item)

        local text

        if is_directory(item) then

            text =
                "▸  " .. name

        elseif is_audio(name) then

            text =
                "♫  " .. name

        else

            text =
                "•  " .. name

        end

        local b =
            ui.button(
                text,
                8,
                y,
                W - 16,
                30,
                function()

                    if is_directory(item) then

                        current_sd_path =
                            join_path(
                                current_sd_path,
                                name
                            )

                        show_folders()

                        return

                    end

                    if is_audio(name) then

                        current_playlist =
                            build_sd_playlist()

                        current_playlist_name =
                            "SD"

                        local wanted =
                            "sd:" ..
                            join_path(
                                current_sd_path,
                                name
                            )

                        for i, track in
                            ipairs(
                                current_playlist
                            )
                        do

                            if track.path ==
                                wanted
                            then

                                selected_index =
                                    i

                                selected_track =
                                    track

                                previous_screen =
                                    SCREEN_FOLDERS

                                show_player()

                                return

                            end

                        end

                    end

                end
            )

        list_buttons[#list_buttons + 1] =
            b

        y = y + 34

        count =
            count + 1

    end

end

------------------------------------------------------------
-- FAVORITES
------------------------------------------------------------

function show_favorites()

    screen =
        SCREEN_FAVORITES

    clear_buttons()

    ui.scroll(true)

    header(
        "FAVORITES",
        tostring(#favorites) ..
        " saved tracks"
    )

    ui.button(
        "‹  HOME",
        8,
        50,
        90,
        28,
        function()

            show_home()

        end
    )

    local y = 88

    if #favorites == 0 then

        ui.label(
            "No favorites yet.",
            8,
            y,
            12,
            C.sub
        )

        return

    end

    local max =
        math.min(
            #favorites,
            8
        )

    for i = 1, max do

        local item =
            favorites[i]

        local index =
            i

        local b =
            ui.button(
                "★  " ..
                item.name,
                8,
                y,
                W - 16,
                30,
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

        y = y + 34

    end

end

------------------------------------------------------------
-- PLAYER
------------------------------------------------------------

function show_player()

    screen =
        SCREEN_PLAYER

    clear_buttons()

    ui.scroll(true)

    header(
        "NOW PLAYING",
        current_playlist_name
    )

    ui.label(
        "♫",
        125,
        52,
        42,
        C.accent
    )

    if selected_track then

        track_line =
            ui.label(
                selected_track.name,
                10,
                105,
                15,
                C.text
            )

        track_line:width(
            W - 20
        )

        local info =
            selected_track.type ..
            "  •  " ..
            string.upper(
                selected_track.source
            )

        subtitle_line =
            ui.label(
                info,
                10,
                130,
                11,
                C.sub
            )

        subtitle_line:width(
            W - 20
        )

        path_line =
            ui.label(
                selected_track.path,
                10,
                151,
                9,
                C.sub
            )

        path_line:width(
            W - 20
        )

    end

    state_line =
        ui.label(
            "State: " ..
            player_state,
            10,
            176,
            11,
            C.accent
        )

    --------------------------------------------------------
    -- PREVIOUS
    --------------------------------------------------------

    ui.button(
        "‹",
        8,
        210,
        86,
        42,
        function()

            previous_track()

            show_player()

        end
    )

    --------------------------------------------------------
    -- PLAY / PAUSE
    --------------------------------------------------------

    local center_text

    if player_state == "playing" then

        center_text =
            "Ⅱ"

    else

        center_text =
            "▶"

    end

    ui.button(
        center_text,
        101,
        210,
        98,
        42,
        function()

            toggle_pause()

            show_player()

        end
    )

    --------------------------------------------------------
    -- NEXT
    --------------------------------------------------------

    ui.button(
        "›",
        206,
        210,
        86,
        42,
        function()

            next_track()

            show_player()

        end
    )

    --------------------------------------------------------
    -- STOP
    --------------------------------------------------------

    ui.button(
        "■  STOP",
        8,
        260,
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

    --------------------------------------------------------
    -- FAVORITE
    --------------------------------------------------------

    local favorite_label

    if selected_track and
       is_favorite(
           selected_track.path
       )
    then

        favorite_label =
            "★  REMOVE FAVORITE"

    else

        favorite_label =
            "☆  ADD TO FAVORITES"

    end

    ui.button(
        favorite_label,
        8,
        302,
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

    --------------------------------------------------------
    -- BACK
    --------------------------------------------------------

    ui.button(
        "‹  BACK",
        8,
        344,
        W - 16,
        30,
        function()

            if previous_screen ==
                SCREEN_FAVORITES
            then

                show_favorites()

            elseif previous_screen ==
                SCREEN_FOLDERS
            then

                show_folders()

            else

                show_music()

            end

        end
    )

end

------------------------------------------------------------
-- OPEN
------------------------------------------------------------

function app.on_open(w, h)

    W =
        w or 300

    H =
        h or 400

    --------------------------------------------------------
    -- Reset runtime state.
    --------------------------------------------------------

    screen =
        SCREEN_HOME

    current_sd_path =
        "/"

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

    --------------------------------------------------------
    -- Build app playlist.
    --------------------------------------------------------

    music_playlist = {}

    for _, track in
        ipairs(APP_TRACKS)
    do

        music_playlist[#music_playlist + 1] =
            {
                name = track.name,
                path = track.path,
                source = SOURCE_APP,
                type = track.type
            }

    end

    current_playlist =
        music_playlist

    current_playlist_name =
        "Music"

    --------------------------------------------------------
    -- Load favorites.
    --------------------------------------------------------

    load_favorites()

    --------------------------------------------------------
    -- Capability check.
    --------------------------------------------------------

    local caps =
        sys.caps()

    if not caps then

        ui.label(
            "MUSIC PLAYER",
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

    if not caps.audio or
       not audio
    then

        ui.label(
            "MUSIC PLAYER",
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

    --------------------------------------------------------
    -- HOME
    --------------------------------------------------------

    show_home()

end

------------------------------------------------------------
-- CLOSE
------------------------------------------------------------

function app.on_close()

    if audio and
       audio.stop
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

------------------------------------------------------------
-- INPUT
------------------------------------------------------------

function app.on_input(ev)

    -- Buttons handle application navigation.
    -- No guessed keyboard API is used.

end

------------------------------------------------------------

return app
