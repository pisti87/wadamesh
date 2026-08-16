-- WADAMESH Deadline Diary
-- Version 1.1
--
-- Lightweight deadline / task diary.
--
-- Main functions:
--   * daily deadline list
--   * previous / next day
--   * create / edit / delete
--   * date and time
--   * priority
--   * completed state
--   * overdue indication
--   * persistent store
--   * keyboard and touch support
--   * deadline notification
--
-- The implementation deliberately uses only the WADAMESH APIs
-- already used by the supplied Calendar/reference applications.

local ui = wada.ui
local sys = wada.sys
local store = wada.store
local timer = wada.timer

local C = ui.colors
local app = {}

--------------------------------------------------
-- Configuration
--------------------------------------------------

local MAX_TASKS = 48
local TITLE_MAX = 32

local HEADER_H = 30
local FOOTER_H = 26
local ROW_H = 30
local FIRST_ROW_Y = 34

--------------------------------------------------
-- UI state
--------------------------------------------------

local cv = nil
local status_label = nil

local screen_w = 300
local screen_h = 220

--------------------------------------------------
-- Clock state
--------------------------------------------------

local today_year = 2026
local today_month = 1
local today_day = 1

local current_hour = 0
local current_minute = 0
local current_second = 0

local clock_valid = false

--------------------------------------------------
-- Selected date
--------------------------------------------------

local selected_year = 2026
local selected_month = 1
local selected_day = 1

--------------------------------------------------
-- Application view
--------------------------------------------------

local view = "list"
local selected_task = 1

--------------------------------------------------
-- Editor
--
-- 1 = date
-- 2 = time
-- 3 = title
-- 4 = priority
-- 5 = done
-- 6 = save
--------------------------------------------------

local editor_field = 1

local editor_year = 2026
local editor_month = 1
local editor_day = 1
local editor_hour = 12
local editor_minute = 0
local editor_title = ""
local editor_priority = false
local editor_done = false
local editor_slot = nil

--------------------------------------------------
-- Task data
--------------------------------------------------

local tasks = {}

--------------------------------------------------
-- Alarm state
--
-- last_scan_key is the last minute checked while the
-- application was running. This prevents a deadline from
-- being missed when a timer callback happens slightly late.
--------------------------------------------------

local last_scan_key = nil
local alarmed_slots = {}

--------------------------------------------------
-- Names
--------------------------------------------------

local month_names = {
    "January", "February", "March", "April",
    "May", "June", "July", "August",
    "September", "October", "November", "December"
}

local weekday_long = {
    "Monday", "Tuesday", "Wednesday", "Thursday",
    "Friday", "Saturday", "Sunday"
}

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function number_value(value, fallback)
    if type(value) == "number" then
        return value
    end

    if type(value) == "string" then
        local n = tonumber(value)

        if n ~= nil then
            return n
        end
    end

    return fallback
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

local function is_leap_year(year)
    if year % 400 == 0 then
        return true
    end

    if year % 100 == 0 then
        return false
    end

    return year % 4 == 0
end

local function days_in_month(year, month)
    if month == 2 then
        if is_leap_year(year) then
            return 29
        end

        return 28
    end

    if month == 4 or month == 6 or
       month == 9 or month == 11 then
        return 30
    end

    return 31
end

-- 0 = Monday ... 6 = Sunday
local function weekday(year, month, day)
    local m = month
    local y = year

    if m < 3 then
        m = m + 12
        y = y - 1
    end

    local k = y % 100
    local j = math.floor(y / 100)

    local h = (
        day +
        math.floor((13 * (m + 1)) / 5) +
        k +
        math.floor(k / 4) +
        math.floor(j / 4) +
        5 * j
    ) % 7

    local result = h - 2

    if result < 0 then
        result = result + 7
    end

    return result
end

local function make_date(year, month, day)
    return string.format(
        "%04d-%02d-%02d",
        year,
        month,
        day
    )
end

local function make_time(hour, minute)
    return string.format(
        "%02d:%02d",
        hour,
        minute
    )
end

local function make_datetime(year, month, day, hour, minute)
    return make_date(year, month, day) ..
        " " ..
        make_time(hour, minute)
end

--------------------------------------------------
-- Task storage
--------------------------------------------------

local function task_key(slot, field)
    return "deadline_e" .. tostring(slot) .. "_" .. field
end

local function load_tasks()
    tasks = {}

    for slot = 1, MAX_TASKS do
        local date = store.get(
            task_key(slot, "date"),
            ""
        )

        local time = store.get(
            task_key(slot, "time"),
            ""
        )

        local title = store.get(
            task_key(slot, "title"),
            ""
        )

        local done = store.get(
            task_key(slot, "done"),
            "0"
        )

        local priority = store.get(
            task_key(slot, "priority"),
            "0"
        )

        if date ~= nil and tostring(date) ~= "" and
           title ~= nil and tostring(title) ~= "" then

            tasks[#tasks + 1] = {
                slot = slot,
                date = tostring(date),
                time = tostring(time or ""),
                title = tostring(title),
                done = tostring(done or "0") == "1",
                priority = tostring(priority or "0") == "1"
            }
        end
    end
end

local function find_free_task_slot()
    for slot = 1, MAX_TASKS do
        local date = store.get(
            task_key(slot, "date"),
            ""
        )

        if date == nil or tostring(date) == "" then
            return slot
        end
    end

    return nil
end

local function save_task(slot)
    local date = make_date(
        editor_year,
        editor_month,
        editor_day
    )

    local time = make_time(
        editor_hour,
        editor_minute
    )

    store.set(task_key(slot, "date"), date)
    store.set(task_key(slot, "time"), time)
    store.set(task_key(slot, "title"), editor_title)
    store.set(
        task_key(slot, "done"),
        editor_done and "1" or "0"
    )
    store.set(
        task_key(slot, "priority"),
        editor_priority and "1" or "0"
    )
end

local function delete_task(task)
    if task == nil or task.slot == nil then
        return
    end

    local slot = task.slot

    store.set(task_key(slot, "date"), "")
    store.set(task_key(slot, "time"), "")
    store.set(task_key(slot, "title"), "")
    store.set(task_key(slot, "done"), "")
    store.set(task_key(slot, "priority"), "")

    alarmed_slots[slot] = nil
end

--------------------------------------------------
-- Task queries
--------------------------------------------------

local function tasks_for_date(year, month, day)
    local result = {}
    local wanted = make_date(year, month, day)

    for i = 1, #tasks do
        local task = tasks[i]

        if task ~= nil and task.date == wanted then
            result[#result + 1] = task
        end
    end

    -- Chronological insertion sort.
    for i = 2, #result do
        local item = result[i]
        local j = i - 1

        while j >= 1 and
              result[j].time > item.time do

            result[j + 1] = result[j]
            j = j - 1
        end

        result[j + 1] = item
    end

    return result
end

local function task_datetime(task)
    if task == nil then
        return ""
    end

    return tostring(task.date or "") ..
        " " ..
        tostring(task.time or "")
end

local function current_datetime()
    if not clock_valid then
        return ""
    end

    return make_datetime(
        today_year,
        today_month,
        today_day,
        current_hour,
        current_minute
    )
end

local function task_is_overdue(task)
    if task == nil or task.done then
        return false
    end

    local due = task_datetime(task)
    local now = current_datetime()

    if due == "" or now == "" then
        return false
    end

    return due < now
end

--------------------------------------------------
-- System clock
--------------------------------------------------

local function update_system_time()
    local epoch = sys.epoch()

    if epoch == nil then
        clock_valid = false
        return false
    end

    local d = sys.datetime()

    if d == nil then
        clock_valid = false
        return false
    end

    if d.year == nil or
       d.month == nil or
       d.day == nil or
       d.hour == nil or
       d.min == nil or
       d.sec == nil then

        clock_valid = false
        return false
    end

    today_year = number_value(d.year, today_year)

    today_month = clamp(
        number_value(d.month, today_month),
        1,
        12
    )

    today_day = clamp(
        number_value(d.day, today_day),
        1,
        days_in_month(
            today_year,
            today_month
        )
    )

    current_hour = clamp(
        number_value(d.hour, 0),
        0,
        23
    )

    current_minute = clamp(
        number_value(d.min, 0),
        0,
        59
    )

    current_second = clamp(
        number_value(d.sec, 0),
        0,
        59
    )

    clock_valid = true

    return true
end

--------------------------------------------------
-- Status
--------------------------------------------------

local function set_status(text)
    if status_label ~= nil then
        status_label:set(text)
        status_label:color(C.sub)
    end
end

--------------------------------------------------
-- Draw list
--------------------------------------------------

local function draw_list()
    if cv == nil then
        return
    end

    cv:fill(0x101418)

    local wd = weekday(
        selected_year,
        selected_month,
        selected_day
    )

    local date_title =
        weekday_long[wd + 1] ..
        " " ..
        tostring(selected_day) ..
        " " ..
        month_names[selected_month]

    cv:text(
        5,
        3,
        date_title,
        C.text,
        14
    )

    if clock_valid then
        cv:text(
            screen_w - 48,
            5,
            string.format(
                "%02d:%02d",
                current_hour,
                current_minute
            ),
            C.accent,
            11
        )
    end

    local list = tasks_for_date(
        selected_year,
        selected_month,
        selected_day
    )

    if #list == 0 then
        cv:text(
            8,
            54,
            "No deadlines",
            C.sub,
            14
        )
    else
        local y = FIRST_ROW_Y

        for i = 1, #list do
            local task = list[i]

            if task ~= nil then
                local selected = i == selected_task
                local overdue = task_is_overdue(task)

                if selected then
                    cv:rect(
                        3,
                        y - 2,
                        screen_w - 6,
                        27,
                        C.accent,
                        true,
                        3
                    )
                end

                local text_color = C.text

                if selected then
                    text_color = C.bg
                end

                local prefix = "[ ] "

                if task.done then
                    prefix = "[x] "
                elseif overdue then
                    prefix = "[>] "
                elseif task.priority then
                    prefix = "[!] "
                end

                local prefix_color = C.sub

                if overdue or task.priority then
                    prefix_color = C.bad
                end

                if selected then
                    prefix_color = C.bg
                end

                cv:text(
                    6,
                    y,
                    prefix,
                    prefix_color,
                    10
                )

                cv:text(
                    42,
                    y,
                    task.time,
                    selected and C.bg or C.accent,
                    11
                )

                local title_text = task.title

                if #title_text > 28 then
                    title_text =
                        string.sub(
                            title_text,
                            1,
                            27
                        ) .. "."
                end

                cv:text(
                    88,
                    y,
                    title_text,
                    text_color,
                    11
                )

                y = y + ROW_H

                if y > screen_h - FOOTER_H - 4 then
                    break
                end
            end
        end
    end

    local total = #list
    local done_count = 0
    local overdue_count = 0

    for i = 1, total do
        if list[i].done then
            done_count = done_count + 1
        elseif task_is_overdue(list[i]) then
            overdue_count = overdue_count + 1
        end
    end

    local summary =
        tostring(done_count) ..
        "/" ..
        tostring(total)

    if overdue_count > 0 then
        summary =
            summary ..
            "  overdue:" ..
            tostring(overdue_count)
    end

    cv:text(
        5,
        screen_h - FOOTER_H - 3,
        summary,
        C.sub,
        10
    )

    set_status(
        "W/Z task A/D day N new X done R del Q back"
    )
end

--------------------------------------------------
-- Draw editor
--------------------------------------------------

local function draw_editor()
    if cv == nil then
        return
    end

    cv:fill(0x101418)

    local heading = "New Deadline"

    if editor_slot ~= nil then
        heading = "Edit Deadline"
    end

    cv:text(
        5,
        3,
        heading,
        C.text,
        15
    )

    local date_text = make_date(
        editor_year,
        editor_month,
        editor_day
    )

    local time_text = make_time(
        editor_hour,
        editor_minute
    )

    local title_text = editor_title

    if title_text == "" then
        title_text = "<type title>"
    end

    local priority_text = "Priority: normal"

    if editor_priority then
        priority_text = "Priority: HIGH"
    end

    local done_text = "Done: no"

    if editor_done then
        done_text = "Done: yes"
    end

    local fields = {
        "Date: " .. date_text,
        "Time: " .. time_text,
        "Title: " .. title_text,
        priority_text,
        done_text,
        "SAVE"
    }

    local y = 32

    for i = 1, #fields do
        local color = C.text

        if i == editor_field then
            color = C.accent
        end

        cv:text(
            5,
            y,
            fields[i],
            color,
            12
        )

        y = y + 28
    end

    if editor_field == 3 then
        set_status(
            "Type title  Backspace delete  Enter next"
        )
    else
        set_status(
            "W/Z field  A/D value  Enter next  Q back"
        )
    end
end

--------------------------------------------------
-- Editor open
--------------------------------------------------

local function open_editor(task)
    if task ~= nil then
        editor_slot = task.slot

        local y = tonumber(
            string.sub(task.date, 1, 4)
        )

        local m = tonumber(
            string.sub(task.date, 6, 7)
        )

        local d = tonumber(
            string.sub(task.date, 9, 10)
        )

        local hh = tonumber(
            string.sub(task.time, 1, 2)
        )

        local mm = tonumber(
            string.sub(task.time, 4, 5)
        )

        editor_year = y or selected_year

        editor_month = clamp(
            m or selected_month,
            1,
            12
        )

        editor_day = clamp(
            d or selected_day,
            1,
            days_in_month(
                editor_year,
                editor_month
            )
        )

        editor_hour = clamp(
            hh or 12,
            0,
            23
        )

        editor_minute = clamp(
            mm or 0,
            0,
            59
        )

        editor_title = tostring(
            task.title or ""
        )

        editor_priority = task.priority == true
        editor_done = task.done == true
    else
        editor_slot = nil

        editor_year = selected_year
        editor_month = selected_month
        editor_day = selected_day

        editor_hour = current_hour

        editor_minute =
            math.floor(current_minute / 5) * 5

        editor_title = ""
        editor_priority = false
        editor_done = false
    end

    editor_field = 1
    view = "editor"

    draw_editor()
end

--------------------------------------------------
-- Save editor
--------------------------------------------------

local function save_editor()
    if editor_title == nil then
        editor_title = ""
    end

    if editor_title == "" then
        sys.toast(
            "Title required",
            1200
        )
        return
    end

    local slot = editor_slot

    if slot == nil then
        slot = find_free_task_slot()
    end

    if slot == nil then
        sys.toast(
            "Diary full",
            1500
        )
        return
    end

    save_task(slot)
    load_tasks()

    if editor_slot ~= nil then
        sys.toast(
            "Deadline updated",
            900
        )
    else
        sys.toast(
            "Deadline saved",
            900
        )
    end

    selected_year = editor_year
    selected_month = editor_month
    selected_day = editor_day
    selected_task = 1

    view = "list"

    draw_list()
end

--------------------------------------------------
-- Toggle selected task
--------------------------------------------------

local function toggle_selected_task()
    local list = tasks_for_date(
        selected_year,
        selected_month,
        selected_day
    )

    if #list == 0 then
        return
    end

    selected_task = clamp(
        selected_task,
        1,
        #list
    )

    local task = list[selected_task]

    if task == nil then
        return
    end

    local new_value = task.done and "0" or "1"

    store.set(
        task_key(task.slot, "done"),
        new_value
    )

    load_tasks()

    if new_value == "1" then
        alarmed_slots[task.slot] = true
    else
        alarmed_slots[task.slot] = nil
    end

    sys.toast(
        new_value == "1"
            and "Completed"
            or "Pending",
        800
    )

    draw_list()
end

--------------------------------------------------
-- Delete confirmation
--------------------------------------------------

local delete_confirm = false

local function cancel_delete()
    delete_confirm = false
    draw_list()
end

local function confirm_delete()
    local list = tasks_for_date(
        selected_year,
        selected_month,
        selected_day
    )

    if #list == 0 then
        delete_confirm = false
        sys.toast(
            "No deadlines",
            800
        )
        return
    end

    selected_task = clamp(
        selected_task,
        1,
        #list
    )

    local task = list[selected_task]

    if task == nil then
        delete_confirm = false
        return
    end

    delete_task(task)
    load_tasks()

    if selected_task > #list then
        selected_task = #list
    end

    if selected_task < 1 then
        selected_task = 1
    end

    delete_confirm = false

    sys.toast(
        "Deadline deleted",
        900
    )

    draw_list()
end

local function draw_delete_confirmation()
    if cv == nil then
        return
    end

    cv:fill(0x101418)

    cv:text(
        8,
        35,
        "Delete deadline?",
        C.text,
        16
    )

    local list = tasks_for_date(
        selected_year,
        selected_month,
        selected_day
    )

    local task = list[selected_task]

    if task ~= nil then
        local title = task.title

        if #title > 27 then
            title = string.sub(title, 1, 26) .. "."
        end

        cv:text(
            8,
            70,
            title,
            C.sub,
            12
        )
    end

    cv:text(
        20,
        120,
        "S = Delete",
        C.bad,
        13
    )

    cv:text(
        20,
        150,
        "Q = Cancel",
        C.accent,
        13
    )

    set_status(
        "Confirm delete: S yes / Q no"
    )
end

--------------------------------------------------
-- Date navigation
--------------------------------------------------

local function previous_day()
    selected_day = selected_day - 1

    if selected_day < 1 then
        selected_month = selected_month - 1

        if selected_month < 1 then
            selected_month = 12
            selected_year = selected_year - 1
        end

        selected_day = days_in_month(
            selected_year,
            selected_month
        )
    end

    selected_task = 1
end

local function next_day()
    selected_day = selected_day + 1

    local maximum = days_in_month(
        selected_year,
        selected_month
    )

    if selected_day > maximum then
        selected_day = 1
        selected_month = selected_month + 1

        if selected_month > 12 then
            selected_month = 1
            selected_year = selected_year + 1
        end
    end

    selected_task = 1
end

--------------------------------------------------
-- Editor date navigation
--------------------------------------------------

local function editor_previous_day()
    editor_day = editor_day - 1

    if editor_day < 1 then
        editor_month = editor_month - 1

        if editor_month < 1 then
            editor_month = 12
            editor_year = editor_year - 1
        end

        editor_day = days_in_month(
            editor_year,
            editor_month
        )
    end
end

local function editor_next_day()
    editor_day = editor_day + 1

    local maximum = days_in_month(
        editor_year,
        editor_month
    )

    if editor_day > maximum then
        editor_day = 1
        editor_month = editor_month + 1

        if editor_month > 12 then
            editor_month = 1
            editor_year = editor_year + 1
        end
    end
end

--------------------------------------------------
-- Editor movement
--------------------------------------------------

local function editor_up()
    if editor_field == 1 then
        editor_previous_day()

    elseif editor_field == 2 then
        editor_hour = editor_hour - 1

        if editor_hour < 0 then
            editor_hour = 23
        end

    elseif editor_field == 4 then
        editor_priority = not editor_priority

    elseif editor_field == 5 then
        editor_done = not editor_done
    end
end

local function editor_down()
    if editor_field == 1 then
        editor_next_day()

    elseif editor_field == 2 then
        editor_hour = editor_hour + 1

        if editor_hour > 23 then
            editor_hour = 0
        end

    elseif editor_field == 4 then
        editor_priority = not editor_priority

    elseif editor_field == 5 then
        editor_done = not editor_done
    end
end

local function editor_left()
    if editor_field == 1 then
        editor_previous_day()

    elseif editor_field == 2 then
        editor_minute = editor_minute - 5

        if editor_minute < 0 then
            editor_minute = 55
        end
    end
end

local function editor_right()
    if editor_field == 1 then
        editor_next_day()

    elseif editor_field == 2 then
        editor_minute = editor_minute + 5

        if editor_minute > 59 then
            editor_minute = 0
        end
    end
end

--------------------------------------------------
-- Keyboard helpers
--------------------------------------------------

local function is_enter(key)
    return key == "ENTER" or
           key == "Enter" or
           key == "RETURN" or
           key == "\r"
end

local function is_backspace(key)
    return key == "BACKSPACE" or
           key == "Backspace"
end

local function is_escape(key)
    return key == "ESC" or
           key == "Escape"
end

--------------------------------------------------
-- Keyboard handling
--------------------------------------------------

local function handle_key(ev)
    if ev == nil or ev.key == nil then
        return
    end

    local key = tostring(ev.key)

    --------------------------------------------------
    -- Delete confirmation has priority.
    --------------------------------------------------

    if delete_confirm then
        if is_escape(key) or
           key == "q" or
           key == "Q" then

            cancel_delete()
            return
        end

        if key == "s" or
           key == "S" or
           is_enter(key) then

            confirm_delete()
            return
        end

        return
    end

    --------------------------------------------------
    -- Back from editor.
    --------------------------------------------------

    if view == "editor" then
        if is_escape(key) or
           key == "q" or
           key == "Q" then

            view = "list"
            draw_list()
            return
        end

        --------------------------------------------------
        -- Title field is a real text-entry mode.
        --
        -- IMPORTANT:
        -- W/A/S/D/Z/P are NOT treated as navigation here.
        -- This fixes the previous bug where words such as
        -- "Shopping" could not be typed correctly.
        --------------------------------------------------

        if editor_field == 3 then
            if is_backspace(key) then
                if #editor_title > 0 then
                    editor_title = string.sub(
                        editor_title,
                        1,
                        #editor_title - 1
                    )
                end

                draw_editor()
                return
            end

            if is_enter(key) then
                editor_field = 4
                draw_editor()
                return
            end

            if #key == 1 and
               #editor_title < TITLE_MAX then

                local byte = string.byte(key)

                if byte ~= nil and
                   byte >= 32 and
                   byte <= 126 then

                    editor_title =
                        editor_title .. key

                    draw_editor()
                end
            end

            return
        end

        --------------------------------------------------
        -- Editor navigation fields.
        --------------------------------------------------

        if key == "w" or key == "W" then
            editor_up()
            draw_editor()
            return
        end

        if key == "z" or key == "Z" then
            editor_down()
            draw_editor()
            return
        end

        if key == "a" or key == "A" then
            editor_left()
            draw_editor()
            return
        end

        if key == "d" or key == "D" then
            editor_right()
            draw_editor()
            return
        end

        if key == "p" or key == "P" then
            if editor_field == 4 then
                editor_priority =
                    not editor_priority
                draw_editor()
            elseif editor_field == 5 then
                editor_done = not editor_done
                draw_editor()
            end

            return
        end

        if is_enter(key) or
           key == "s" or
           key == "S" then

            if editor_field < 6 then
                editor_field =
                    editor_field + 1
                draw_editor()
            else
                save_editor()
            end

            return
        end

        return
    end

    --------------------------------------------------
    -- List view.
    --------------------------------------------------

    if view == "list" then
        if is_escape(key) then
            return
        end

        if key == "w" or key == "W" then
            local list = tasks_for_date(
                selected_year,
                selected_month,
                selected_day
            )

            if #list > 0 then
                selected_task =
                    selected_task - 1

                if selected_task < 1 then
                    selected_task = #list
                end
            end

            draw_list()
            return
        end

        if key == "z" or key == "Z" then
            local list = tasks_for_date(
                selected_year,
                selected_month,
                selected_day
            )

            if #list > 0 then
                selected_task =
                    selected_task + 1

                if selected_task > #list then
                    selected_task = 1
                end
            end

            draw_list()
            return
        end

        if key == "a" or key == "A" then
            previous_day()
            draw_list()
            return
        end

        if key == "d" or key == "D" then
            next_day()
            draw_list()
            return
        end

        if key == "n" or key == "N" then
            open_editor(nil)
            return
        end

        if key == "x" or key == "X" or
           key == "SPACE" or key == " " then

            toggle_selected_task()
            return
        end

        if key == "r" or key == "R" then
            local list = tasks_for_date(
                selected_year,
                selected_month,
                selected_day
            )

            if #list > 0 then
                selected_task = clamp(
                    selected_task,
                    1,
                    #list
                )

                delete_confirm = true
                draw_delete_confirmation()
            end

            return
        end

        if key == "s" or key == "S" or
           is_enter(key) then

            local list = tasks_for_date(
                selected_year,
                selected_month,
                selected_day
            )

            if #list > 0 then
                selected_task = clamp(
                    selected_task,
                    1,
                    #list
                )

                open_editor(
                    list[selected_task]
                )
            else
                open_editor(nil)
            end

            return
        end
    end
end

--------------------------------------------------
-- Input
--------------------------------------------------

function app.on_input(ev)
    if ev == nil then
        return
    end

    if ev.type == "key" then
        handle_key(ev)
        return
    end

    --------------------------------------------------
    -- Swipe navigation.
    --------------------------------------------------

    if ev.type == "swipe" then
        local direction = ev.dir

        if direction == nil then
            return
        end

        if view == "list" then
            if direction == "up" then
                handle_key({
                    type = "key",
                    key = "W"
                })
            elseif direction == "down" then
                handle_key({
                    type = "key",
                    key = "Z"
                })
            elseif direction == "left" then
                handle_key({
                    type = "key",
                    key = "A"
                })
            elseif direction == "right" then
                handle_key({
                    type = "key",
                    key = "D"
                })
            end

            return
        end

        if view == "editor" then
            -- Do not turn swipes into W/A/S/D while
            -- typing a title.
            if editor_field == 3 then
                return
            end

            if direction == "up" then
                handle_key({
                    type = "key",
                    key = "W"
                })
            elseif direction == "down" then
                handle_key({
                    type = "key",
                    key = "Z"
                })
            elseif direction == "left" then
                handle_key({
                    type = "key",
                    key = "A"
                })
            elseif direction == "right" then
                handle_key({
                    type = "key",
                    key = "D"
                })
            end

            return
        end
    end

    --------------------------------------------------
    -- Touch.
    --
    -- The footer buttons are handled by ui.button.
    -- We deliberately do NOT treat the whole footer as
    -- "New", avoiding the previous button/input conflict.
    --------------------------------------------------

    if ev.type == "down" then
        local x = number_value(ev.x, 0)
        local y = number_value(ev.y, 0)

        if view == "list" then
            if y >= FIRST_ROW_Y and
               y < screen_h - FOOTER_H then

                local index = math.floor(
                    (y - FIRST_ROW_Y) / ROW_H
                ) + 1

                local list = tasks_for_date(
                    selected_year,
                    selected_month,
                    selected_day
                )

                if index >= 1 and
                   index <= #list then

                    selected_task = index
                    draw_list()
                end
            end

        elseif view == "editor" then
            if y >= 30 and
               y < 30 + (6 * 28) then

                local field = math.floor(
                    (y - 30) / 28
                ) + 1

                editor_field = clamp(
                    field,
                    1,
                    6
                )

                draw_editor()
            end
        end

        -- Avoid an unused-variable warning while keeping
        -- the coordinate available for future touch actions.
        if x < -1 then
            return
        end
    end
end

--------------------------------------------------
-- Deadline notification
--------------------------------------------------

local function check_deadlines()
    if not clock_valid then
        return
    end

    local now_key = current_datetime()

    if now_key == "" then
        return
    end

    -- First scan establishes the baseline. This prevents
    -- opening the app after an old deadline from immediately
    -- producing an alarm.
    if last_scan_key == nil then
        last_scan_key = now_key
        return
    end

    if now_key == last_scan_key then
        return
    end

    for i = 1, #tasks do
        local task = tasks[i]

        if task ~= nil and
           not task.done and
           task.date ~= nil and
           task.time ~= nil then

            local due_key = task_datetime(task)

            if due_key > last_scan_key and
               due_key <= now_key and
               alarmed_slots[task.slot] ~= true then

                sys.beep()

                alarmed_slots[task.slot] = true

                if status_label ~= nil then
                    local alarm_text =
                        "DEADLINE: " ..
                        tostring(task.title)

                    status_label:set(
                        alarm_text
                    )

                    status_label:color(
                        C.bad
                    )
                end

                -- One audible notification per scan is
                -- enough; remaining deadlines stay visible
                -- as overdue.
                break
            end
        end
    end

    last_scan_key = now_key

    if view == "list" then
        draw_list()
    end
end

--------------------------------------------------
-- Tick
--------------------------------------------------

function app.on_tick(dt)
    if not update_system_time() then
        return
    end

    check_deadlines()
end

--------------------------------------------------
-- Open
--------------------------------------------------

function app.on_open(w, h)
    screen_w = w or 300
    screen_h = h or 220

    update_system_time()

    selected_year = today_year
    selected_month = today_month
    selected_day = today_day

    load_tasks()

    cv = ui.canvas(
        screen_w,
        screen_h
    )

    cv:pos(0, 0)

    -- Status occupies the left side of the footer.
    status_label = ui.label(
        "W/Z task  A/D day",
        4,
        screen_h - FOOTER_H,
        9,
        C.sub
    )

    status_label:width(
        screen_w - 150
    )

    --------------------------------------------------
    -- Touch buttons.
    --------------------------------------------------

    ui.button(
        "New",
        screen_w - 148,
        screen_h - 24,
        44,
        22,
        function()
            open_editor(nil)
        end
    )

    ui.button(
        "Done",
        screen_w - 100,
        screen_h - 24,
        44,
        22,
        function()
            toggle_selected_task()
        end
    )

    ui.button(
        "Del",
        screen_w - 52,
        screen_h - 24,
        48,
        22,
        function()
            local list = tasks_for_date(
                selected_year,
                selected_month,
                selected_day
            )

            if #list > 0 then
                selected_task = clamp(
                    selected_task,
                    1,
                    #list
                )

                delete_confirm = true
                draw_delete_confirmation()
            end
        end
    )

    --------------------------------------------------
    -- Minute-level timer.
    --
    -- The supplied Calendar reference uses the same
    -- timer API and interval.
    --------------------------------------------------

    timer.every(60000)

    view = "list"
    selected_task = 1
    delete_confirm = false

    -- Establish the initial alarm baseline.
    last_scan_key = current_datetime()

    draw_list()
end

--------------------------------------------------
-- Close
--------------------------------------------------

function app.on_close()
    cv = nil
    status_label = nil
end

return app
