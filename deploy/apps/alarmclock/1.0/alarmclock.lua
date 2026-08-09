```lua
-- WADAMESH Alarm Clock
--
-- Requires the following WADAMESH Lua APIs:
--
--   wada.sys.epoch()
--   wada.sys.datetime()
--   wada.sound.buzzer(melody)
--
-- Controls:
--   Swipe left/right  = select setting
--   Swipe up/down     = change selected value
--   Down/tap          = enable/disable alarm
--
-- Display:
--   Current time
--   Current date
--   Alarm time
--   Alarm state
--
-- The current time comes directly from WADAMESH system time.
-- The alarm is calculated from Unix epoch seconds.

local ui, sys, store, timer =
    wada.ui, wada.sys, wada.store, wada.timer

local C = ui.colors

local app = {}

local cv
local time_lbl
local date_lbl
local alarm_lbl
local status_lbl

local W = 0
local H = 0

local refresh_timer = 0

--------------------------------------------------
-- Alarm configuration
--------------------------------------------------

local alarm_hour = 7
local alarm_min = 0
local alarm_enabled = false

-- Prevent the alarm from repeatedly triggering
-- during the same minute.
local last_alarm_epoch = 0

-- Selected setting:
--
-- 1 = hour
-- 2 = minute
-- 3 = enabled
--
local selected = 1

--------------------------------------------------
-- Storage
--------------------------------------------------

local function load_settings()

    alarm_hour = store.get("alarm_hour", 7)
    alarm_min = store.get("alarm_min", 0)
    alarm_enabled = store.get("alarm_enabled", false)

    if alarm_hour < 0 or alarm_hour > 23 then
        alarm_hour = 7
    end

    if alarm_min < 0 or alarm_min > 59 then
        alarm_min = 0
    end

end


local function save_settings()

    store.set("alarm_hour", alarm_hour)
    store.set("alarm_min", alarm_min)
    store.set("alarm_enabled", alarm_enabled)

end

--------------------------------------------------
-- Time
--------------------------------------------------

local function get_datetime()

    local now = sys.datetime()

    if now == nil then
        return nil
    end

    return now

end


local function get_epoch()

    local epoch = sys.epoch()

    if epoch == nil then
        return 0
    end

    return epoch

end

--------------------------------------------------
-- Buzzer
--------------------------------------------------

-- Short, simple alarm melody.
--
-- The exact melody syntax is interpreted by the
-- WADAMESH buzzer implementation.
--
-- Keep this string easy to change.

local ALARM_MELODY = "C5:150,D5:150,E5:250"

local function play_alarm()

    wada.sound.buzzer(ALARM_MELODY)

end

--------------------------------------------------
-- Alarm checking
--------------------------------------------------

local function check_alarm(now)

    if now == nil then
        return
    end

    if not alarm_enabled then
        return
    end

    if now.hour ~= alarm_hour then
        return
    end

    if now.min ~= alarm_min then
        return
    end

    -- Use the current epoch as the trigger identifier.
    -- This prevents the buzzer from being started
    -- continuously on every on_tick() call.
    --
    -- We intentionally reduce it to the minute.
    local minute_epoch = math.floor(get_epoch() / 60)

    if minute_epoch == 0 then
        return
    end

    if minute_epoch == last_alarm_epoch then
        return
    end

    last_alarm_epoch = minute_epoch

    play_alarm()

end

--------------------------------------------------
-- Formatting
--------------------------------------------------

local function two_digit(value)

    return string.format("%02d", value)

end


local function update_time()

    local now = get_datetime()

    if now == nil then

        time_lbl:set("--:--:--")
        date_lbl:set("----.--.--")
        return

    end

    time_lbl:set(
        string.format(
            "%02d:%02d:%02d",
            now.hour,
            now.min,
            now.sec
        )
    )

    date_lbl:set(
        string.format(
            "%04d.%02d.%02d",
            now.year,
            now.month,
            now.day
        )
    )

    check_alarm(now)

end

--------------------------------------------------
-- Alarm display
--------------------------------------------------

local function update_alarm_display()

    local state

    if alarm_enabled then
        state = "ON"
    else
        state = "OFF"
    end

    local marker = ""

    if selected == 1 then
        marker = ">"
    end

    local hour_text =
        marker .. string.format("%02d", alarm_hour)

    marker = ""

    if selected == 2 then
        marker = ">"
    end

    local min_text =
        marker .. string.format("%02d", alarm_min)

    marker = ""

    if selected == 3 then
        marker = ">"
    end

    local state_text =
        marker .. state

    alarm_lbl:set(
        string.format(
            "Alarm %s:%s  %s",
            hour_text,
            min_text,
            state_text
        )
    )

end

--------------------------------------------------
-- Drawing
--------------------------------------------------

local function draw()

    cv:fill(0x101418)

    ------------------------------------------------
    -- Time
    ------------------------------------------------

    cv:text(
        22,
        20,
        "TIME",
        C.good,
        12
    )

    ------------------------------------------------
    -- Alarm
    ------------------------------------------------

    cv:text(
        22,
        92,
        "ALARM",
        C.good,
        12
    )

    ------------------------------------------------
    -- Selection hint
    ------------------------------------------------

    cv:text(
        22,
        150,
        "Swipe L/R select",
        C.text,
        11
    )

    cv:text(
        22,
        166,
        "Swipe U/D change",
        C.text,
        11
    )

    cv:text(
        22,
        182,
        "Tap to toggle",
        C.text,
        11
    )

end

--------------------------------------------------
-- Input
--------------------------------------------------

local function select_next()

    selected = selected + 1

    if selected > 3 then
        selected = 1
    end

end


local function select_previous()

    selected = selected - 1

    if selected < 1 then
        selected = 3
    end

end


local function increase_selected()

    if selected == 1 then

        alarm_hour = alarm_hour + 1

        if alarm_hour > 23 then
            alarm_hour = 0
        end

        save_settings()

    elseif selected == 2 then

        alarm_min = alarm_min + 1

        if alarm_min > 59 then
            alarm_min = 0
        end

        save_settings()

    elseif selected == 3 then

        alarm_enabled = not alarm_enabled

        save_settings()

    end

end


local function decrease_selected()

    if selected == 1 then

        alarm_hour = alarm_hour - 1

        if alarm_hour < 0 then
            alarm_hour = 23
        end

        save_settings()

    elseif selected == 2 then

        alarm_min = alarm_min - 1

        if alarm_min < 0 then
            alarm_min = 59
        end

        save_settings()

    elseif selected == 3 then

        alarm_enabled = not alarm_enabled

        save_settings()

    end

end

--------------------------------------------------
-- WADAMESH API
--------------------------------------------------

function app.on_open(w, h)

    W = w
    H = h

    load_settings()

    ------------------------------------------------
    -- Labels
    ------------------------------------------------

    time_lbl = ui.label(
        "--:--:--",
        4,
        4,
        28,
        C.text
    )

    date_lbl = ui.label(
        "----.--.--",
        4,
        36,
        14,
        C.text
    )

    alarm_lbl = ui.label(
        "Alarm 07:00 OFF",
        4,
        112,
        14,
        C.text
    )

    status_lbl = ui.label(
        "",
        4,
        132,
        12,
        C.text
    )

    ------------------------------------------------
    -- Canvas
    ------------------------------------------------

    cv = ui.canvas(
        w,
        h
    )

    cv:pos(
        0,
        0
    )

    update_time()
    update_alarm_display()
    draw()

    timer.every(1000)

end


function app.on_input(ev)

    if ev.type == "swipe" then

        if ev.dir == "left" then

            select_previous()

        elseif ev.dir == "right" then

            select_next()

        elseif ev.dir == "up" then

            increase_selected()

        elseif ev.dir == "down" then

            decrease_selected()

        end

        update_alarm_display()
        draw()

    elseif ev.type == "down" then

        alarm_enabled = not alarm_enabled

        save_settings()

        update_alarm_display()
        draw()

    end

end


function app.on_tick(dt)

    update_time()
    update_alarm_display()

end


function app.on_close()

end

return app
```
