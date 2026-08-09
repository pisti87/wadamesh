Development status

This Alarm Clock application is currently a Lua-based prototype/draft. 
The required time and buzzer access is currently proposed as an extension to the WADAMESH Lua API.
The proposed time API is:
```
local epoch = wada.sys.epoch()
```
which would return the current Unix epoch time in seconds.

Optionally:
```
local now = wada.sys.datetime()
```
which would return a Lua table containing the current date and time.
For the alarm sound, the proposed API is:
```
wada.sound.buzzer("...")
```
This would provide Lua access to the buzzer functionality that already exists on the firmware side.

The intended alarm logic is:
```
local now = wada.sys.epoch()

if now >= alarm_epoch then
    wada.sound.buzzer("...")
end
```
Important: these Lua bindings may not yet be available in the released WADAMESH Lua API. 
Therefore, this application should currently be considered a development draft, 
and the required firmware-side Lua bindings still need to be integrated before the application can operate fully.
