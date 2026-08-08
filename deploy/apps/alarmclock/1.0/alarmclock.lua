-- WADAMESH Alarm Clock
-- Android style alarm settings

local ui, sys, store, timer = 
    wada.ui, wada.sys, wada.store, wada.timer

local C = ui.colors

local app = {}

local hour = 7
local minute = 0

local repeat_count = 1
local snooze_min = 5

local enabled = false

local alarm_active = false
local ring_count = 0

local next_alarm_ms = 0


local title
local clock_lbl
local alarm_lbl
local repeat_lbl
local status_lbl



local function save()

    store.set("alarm_hour",hour)
    store.set("alarm_min",minute)
    store.set("alarm_repeat",repeat_count)
    store.set("alarm_snooze",snooze_min)
    store.set("alarm_enabled",enabled)

end



local function load()

    hour = store.get("alarm_hour",7)
    minute = store.get("alarm_min",0)

    repeat_count =
        store.get("alarm_repeat",1)

    snooze_min =
        store.get("alarm_snooze",5)

    enabled =
        store.get("alarm_enabled",false)

end



local function text_update()

    alarm_lbl:set(
        string.format(
        "Alarm %02d:%02d",
        hour,
        minute)
    )


    repeat_lbl:set(
        "Repeat: "..repeat_count..
        "  Snooze "..snooze_min.."m"
    )


    status_lbl:set(
        enabled and "ON" or "OFF"
    )

end



function increase_hour()

    hour=hour+1

    if hour>23 then
        hour=0
    end

    text_update()

end



function decrease_hour()

    hour=hour-1

    if hour<0 then
        hour=23
    end

    text_update()

end



function increase_min()

    minute=minute+1

    if minute>59 then
        minute=0
    end

    text_update()

end



function decrease_min()

    minute=minute-1

    if minute<0 then
        minute=59
    end

    text_update()

end



function change_repeat()

    if repeat_count==1 then
        repeat_count=2
    elseif repeat_count==2 then
        repeat_count=3
    elseif repeat_count==3 then
        repeat_count=5
    else
        repeat_count=1
    end

    text_update()

end



function toggle()

    enabled=not enabled

    save()

    text_update()

end



function alarm_start()

    alarm_active=true
    ring_count=1

    sys.toast(
      "ALARM "..ring_count..
      "/"..repeat_count,
      3000
    )

end



function check_alarm()

    if not enabled then
        return
    end


    -- IDEIGLENES:
    -- ide kerül a GPS/RTC idő összehasonlítás

end




function app.on_open(w,h)

    load()


    title =
    ui.label(
        "Alarm Clock",
        4,4,16,C.accent
    )


    alarm_lbl =
    ui.label(
        "",
        4,35,16,C.text
    )


    repeat_lbl =
    ui.label(
        "",
        4,65,12,C.sub
    )


    status_lbl =
    ui.label(
        "",
        4,95,14,C.good
    )



    ui.button(
        "-H",
        5,130,
        50,30,
        decrease_hour
    )

    ui.button(
        "+H",
        60,130,
        50,30,
        increase_hour
    )


    ui.button(
        "-M",
        120,130,
        50,30,
        decrease_min
    )

    ui.button(
        "+M",
        175,130,
        50,30,
        increase_min
    )



    ui.button(
        "Repeat",
        5,180,
        100,35,
        change_repeat
    )


    ui.button(
        "ON/OFF",
        120,180,
        100,35,
        toggle
    )


    ui.button(
        "SAVE",
        5,230,
        100,35,
        save
    )


    text_update()


    timer.every(1000)

end



function app.on_tick(dt)

    check_alarm()

end



function app.on_close()

    save()

end


return app
