Fejlesztési állapot

Ez az Alarm Clock alkalmazás jelenleg egy Lua-alapú prototípus/vázlat. 
A működéséhez szükséges idő- és buzzer-hozzáférés jelenleg WADAMESH Lua API-bővítésként van javasolva.

A tervezett idő API:
```
local epoch = wada.sys.epoch()
```
amely Unix epoch időt adna vissza másodpercben.

Opcionálisan:
```
local now = wada.sys.datetime()
```
amely egy dátum- és időadatokat tartalmazó Lua táblát adna vissza.
Az ébresztő hangjelzéséhez a javasolt API:
```
wada.sound.buzzer("...")
```
Ez a WADAMESH firmware-ben már meglévő buzzer-kezelés Lua bindingjára épülne.

A tervezett működés:
```
local now = wada.sys.epoch()

if now >= alarm_epoch then
    wada.sound.buzzer("...")
end
```
Fontos: ezek a szükséges Lua bindingok jelenleg még nem feltétlenül érhetők el a WADAMESH kiadott Lua API-jában.
Az alkalmazás ezért jelenleg fejlesztési vázlatnak tekintendő,
 és a teljes működéshez szükséges firmware-oldali Lua bindingok beépítése szükséges.
