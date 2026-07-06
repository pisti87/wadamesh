# Heltec ThinkNode M9 — wadamesh port

Fresh port against `main`, built alongside (not replacing) the Heltec V4 TFT and
LilyGo T-Deck envs. Env name: `ThinkNode_M9_companion_radio_touch`.

## Hardware summary

ESP32-S3R8, LR1110 radio, 2.4" 240x320 **ST7789** TFT (manufacturer-confirmed —
an earlier attempt assumed ILI9341 based on a Meshtastic boot log that, per the
manufacturer, was wrong), full QWERTY keyboard + d-pad + dedicated function
buttons all on one I2C keyboard controller, no touchscreen. CC1167Q GPS, QMI8658
IMU, QMC6309 compass, PCF8563 RTC, 8 MB PSRAM, 16 MB flash.

## Why this needed its own radio_init(), not std_init()

`CustomLR1110` (the core's LR1110 wrapper) has **no `std_init()`** — unlike
`CustomSX1262`/`SX1268`/`LLCC68`. Every existing LR1110 board in MeshCore
(`thinknode_m3`, `minewsemi_me25ls01`) drives the radio by hand: `SPI.setPins()`
→ `SPI.begin()` →
`radio.begin(freq, bw, sf, cr, sync_word, power, preamble, tcxo)` →
`setCRC()`/`explicitHeader()` → optional RF-switch table / boosted-gain.
`variants/thinknode_m9/target.cpp::radio_init()` follows that pattern exactly
(see MeshCore `variants/thinknode_m3/target.cpp` as the reference it's modelled
on).

The radio, the ST7789 panel, and the microSD slot all share one physical SPI
bus. Neither `LILYGO_TDECK` nor `HELTEC_LORA_V4_TFT` is defined for this board,
so `ST7789LCDDisplay` takes its default constructor branch
(`display(&SPI, ...)`) — meaning the display uses the **same** global `SPI`
instance as the radio, matching how the LR1110 reference boards do it (no
separate `HSPI`/local `SPIClass` the way the T-Deck/Heltec-TFT branch does).

## Verified pin map

(Cross-referenced from the Meshtastic `thinknode_m9` boot log against the V1.0
schematic during Specter (ESP-IDF) bring-up; carried over unchanged.)

| Net                          | GPIO            | Notes                                                                                                                                                                                                                                                         |
| ---------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| LR1110 NSS                   | 39              |                                                                                                                                                                                                                                                               |
| LR1110 IRQ (DIO1)            | 42              | also `getIRQGpio()` / sleep wake source                                                                                                                                                                                                                       |
| LR1110 RESET                 | 45              |                                                                                                                                                                                                                                                               |
| LR1110 BUSY                  | 41              |                                                                                                                                                                                                                                                               |
| SPI SCLK                     | 40              | shared: radio + LCD + microSD                                                                                                                                                                                                                                 |
| SPI MISO                     | 38              |                                                                                                                                                                                                                                                               |
| SPI MOSI                     | 47              |                                                                                                                                                                                                                                                               |
| LCD RESET                    | 14              |                                                                                                                                                                                                                                                               |
| LCD DC (RS)                  | 15              | repurposed XTAL_32K_P                                                                                                                                                                                                                                         |
| LCD CS                       | 16              | repurposed XTAL_32K_N                                                                                                                                                                                                                                         |
| Backlight (BL_EN)            | 17              | PNP transistor, **active-LOW**                                                                                                                                                                                                                                |
| Peripheral power rail        | 18              | P-MOS, **active-LOW** (LCD/GPS/sensors)                                                                                                                                                                                                                       |
| microSD                      | SD_MMC          | SDMMC peripheral per the Meshtastic boot log — NOT the shared SPI bus. The earlier "CS=36" reading is an octal-PSRAM pin (GPIO35-37 reserved on the S3R8; driving 36 wedges PSRAM — bring-up #3 hang). Real SDMMC pins pending from the Meshtastic variant.h. |
| Peripheral I2C SDA/SCL       | 7 / 6           | RTC 0x51, IMU 0x6b, compass 0x7c                                                                                                                                                                                                                              |
| Keyboard I2C SDA/SCL         | 20 / 21         | controller @ 0x6c, **own bus** (Wire1)                                                                                                                                                                                                                        |
| Battery ADC                  | 13              | ADC1_CH2, **2:1 divider** (manufacturer-confirmed)                                                                                                                                                                                                            |
| GPS RX/TX                    | 2 / 3           | CC1167Q, UART1                                                                                                                                                                                                                                                |
| GPS EN / ON_OFF / RST / 1PPS | 11 / 10 / 5 / 4 | EN+RST wired; ON_OFF + 1PPS unused                                                                                                                                                                                                                            |
| Buzzer                       | 9               | not yet wired into the firmware                                                                                                                                                                                                                               |
| ESP_WAKEUP (from KB MCU)     | 12              | not wired; behaviour undocumented                                                                                                                                                                                                                             |
| KEY_LED                      | 46              | not wired                                                                                                                                                                                                                                                     |
| User button (BOOT)           | 0               | only direct button besides the keyboard                                                                                                                                                                                                                       |

This turn's corrections vs. the earlier (incorrect) attempt:

- Display is **ST7789**, not ILI9341.
- LR1110 clock: **TCXO mode at 3.3 V** (bring-up build #2). Empirically settled
  on the tester's preproduction unit: Meshtastic's variant logs "using DIO3 as
  TCXO reference voltage at 3.300000 V" + "LR1110 init result 0" on this exact
  device, and our build #1 with tcxo=0 (the earlier active-oscillator theory)
  failed radio init with -707: the chip boots on internal RC (SPI alive) but the
  first command needing the 32 MHz clock is rejected. The schematic's "VTCXO
  rail" powering Y1 is evidently the LR1110's own TCXO-supply output.
- Battery divider is **2:1**, not 1:1 — equal-value resistors still halve the
  voltage regardless of their absolute value; `getBattMilliVolts()`'s `2 *`
  multiplier was wrongly removed on the mistaken belief that "equal resistors"
  meant "no division." Restored.

## Keyboard (confirmed on hardware — `M9Keyboard.h`)

One raw byte per read, controller resolves shift/symbol layers itself:

| Key                  | Raw  | Key          | Raw  |
| -------------------- | ---- | ------------ | ---- |
| left                 | 0xB4 | left_message | 0x81 |
| up                   | 0xB5 | home         | 0x82 |
| down                 | 0xB6 | sub_message  | 0x83 |
| right                | 0xB7 | sub_map      | 0x84 |
| d-pad centre / enter | 0x0D | map          | 0x85 |
| del (backspace)      | 0x08 | hw_back      | 0x86 |
| mic (triangle)       | 0x88 | ctrl         | 0x90 |

Backspace (0x08) and Enter (0x0D) happen to match the values
`UITask.cpp::handleHwKey()` already special-cases for the T-Deck, so typing,
backspace, and Enter-to-send all work as-is. The d-pad/function-key bytes
(0x81–0x90, 0xB4–0xB7) currently fall through unhandled when no text field is
focused — see "Deferred" below.

## What's wired in this patch

- `boards/thinknode_m9.json` — ESP32-S3R8, 16 MB flash, 8 MB PSRAM.
- `variants/thinknode_m9/M9Board.{h,cpp}` — board class: both active-low power
  rails (periph rail + backlight) via `RefCountedDigitalPin`, 1:1 battery
  divider, deep-sleep/wake on LR1110 IRQ.
- `variants/thinknode_m9/target.{h,cpp}` — manual LR1110 `radio_init()`,
  GPS/RTC/sensor wiring, ST7789 display instantiation, `m9SharedSPI()` (mirrors
  the T-Deck's `tdeckSharedSPI()` — used by the SD mount code below).
- `variants/thinknode_m9/M9Keyboard.{h,cpp}` — Wire1 keyboard driver, ring
  buffer, hardware-confirmed keycode sentinels (`M9_KEY_*`).
- `variants/thinknode_m9/partitions_m9_touch.csv` — 16 MB, dual A/B OTA slots
  (copy of the T-Deck's layout; same flash size).
- `platformio.ini` — new `[env:ThinkNode_M9_companion_radio_touch]`.
- `src/ui-touch/device_caps.h` — new `HAS_THINKNODE_M9` capability block;
  `CAP_KEYPAD_NAV`/`CAP_SD`/`CAP_FILESYSTEM` all `1` (see below).
- `src/ui-touch/UITask.cpp`:
  - `HAS_M9_KEYBOARD` added alongside `HAS_TDECK_KEYBOARD` at every _generic_
    "is there a physical keyboard" gate (composer auto-focus, Enter-sends
    toggle, spacebar-lock, secondary-keyboard cycling hint, etc. — 15 sites),
    plus its own poll/drain branch in the per-tick loop (polls `Wire1` directly
    from the UI thread — no core-0 hand-off needed, since this bus has no other
    device on it, unlike the T-Deck's touch+keyboard-shared bus).
  - **microSD**, extended from the T-Deck's existing pattern rather than
    rebuilt: the include block, `fmIsSd()`, the mount/format/click helpers
    (`fmSdTryMount`/`fmSdDoFormat`/etc.), and the Files-manager settings row are
    all now `#if defined(HAS_TDECK_GT911) || defined(HAS_THINKNODE_M9)`,
    swapping `tdeckSharedSPI()` for `m9SharedSPI()` where the bus accessor is
    used. The Home-screen "Files" launcher button is shown for M9 too. NOT
    extended: the wallpaper picker / notification-sound chooser block, which is
    entangled with `tdeckPlayNotifySlot()` (T-Deck's I2S amp) and isn't pure SD
    logic — left T-Deck-only.
  - **D-pad keypad navigation**, built on the SAME generic engine Tanmatsu and
    the T-Deck already share (navFifo, `navMoveDir`/`navSwitchTab`/
    `navPushTap`, the focus group, the secondary LVGL `KEYPAD` indev) —
    `CAP_KEYPAD_NAV` now also covers `HAS_THINKNODE_M9`, the secondary-indev
    registration and `s_kbd_nav`-always-on logic were broadened from
    `CAP_TRACKBALL`-only, and a new `#elif defined(HAS_M9_KEYBOARD)` block in
    `handleHwKey()` (parallel to the T-Deck's WASDZ-letter block) maps the M9's
    _fixed_ hardware d-pad/function-key bytes straight to those same primitives
    instead of going through the programmable letter table. UP/DOWN/LEFT/RIGHT
    move focus or pan the tab bar, the d-pad centre/Enter selects, the dedicated
    HW-back key backs out, and HOME/MAP/MESSAGE jump to those tabs. MIC and CTRL
    have no action bound yet.
- **Keypad nav corrected for cases the initial patch missed**: the wizard was
  unreachable by d-pad at all (handleHwKey()'s touch-only setup-root swallow ran
  before M9's key handling); Enter on a focused button after leaving a field via
  arrows silently no-op'd (stale on-screen-keyboard binding used instead of the
  live group focus); there was no way to leave an edit field via the d-pad; HOME
  didn't close overlays before jumping tabs; and there was no wake-from-idle
  path (M9 has no touch to wake it the way T-Deck/Heltec V4 do). All fixed in
  UITask.cpp — see git history for specifics.
- **Backlight control** (`touchScreenBacklight()`) had no M9 branch at all — the
  idle-off state tracked correctly but the physical backlight never dimmed.
  Added `m9SetBacklight()` (target.h/.cpp) driving the ref-counted GPIO17 pin.

## Deferred — hardware-verify list

These are left intentionally unset/unwired rather than guessed:

1. **RF-switch DIO table — pin assignment confirmed, polarity not.** Cross-
   checked directly against the V1.0 schematic (LR1110/U7 block): DIO5 (pin 20)
   → R20 → net `RFSW0_V1`, DIO6 (pin 19) → R19 → net `RFSW1_V2`, both into the
   switch IC (U8) feeding a single antenna (`RFC` → C74 → L12 → ANT1). DIO7/DIO8
   are unconnected (dangling stubs, no net) — this is a plain 2-pin switch, the
   same shape as `thinknode_m3`'s table, _not_ `t1000-e`/`me25ls01`'s 4-pin
   DIO5-8 scheme. `RF_SWITCH_TABLE` is now **enabled** in `platformio.ini` with
   that DIO5/DIO6 mapping. What's _not_ independently confirmed: U8's part
   number isn't printed on the schematic, so the per-mode HIGH/LOW truth table
   (STBY/RX/TX/TX_HP/…) is carried from the same convention every other 2-pin
   MeshCore LR1110 board uses, not read off a switch-IC datasheet. If TX/RX work
   but seem dead or swapped, that table's RX/TX_HP rows are the first thing to
   flip.
2. **GPS EN polarity / ON_OFF pin / baud rate.** `PIN_GPS_EN_ACTIVE` is left at
   the library default (`HIGH`); GPIO10 (ON_OFF) isn't wired into anything. Baud
   defaults to the library's 9600 fallback (no `GPS_BAUD_RATE` override) —
   confirm against the CC1167Q's actual NMEA baud.
3. **Display rotation.** VERIFIED: `DISPLAY_ROTATION=1` (3 was 180 deg off on
   hardware, bring-up #6). Original note: `DISPLAY_ROTATION=3` was a starting
   guess (matches the T-Deck, same keyboard-below-screen form factor) using
   Adafruit's rotation 0–3 numbering — **this is unrelated to** the raw-MADCTL
   rotation constants found during the earlier ESP-IDF/Specter bring-up (that
   was a different, hand-rolled display driver stack; the numbering doesn't
   carry over).
4. **microSD mount-ladder timing.** The settle-delay/clock ladder in
   `fmSdTryMount()` was tuned against the T-Deck's shared SPI bus electrically.
   M9 shares the same three signals (SCLK/MISO/MOSI) across radio+LCD+SD too,
   but the timing margins haven't been confirmed on real M9 hardware — if SD
   never mounts or mounts unreliably, start here.
5. **Wallpaper picker / notification-sound chooser.** Not extended to M9 — it
   calls `tdeckPlayNotifySlot()` (T-Deck's I2S amp) directly, and M9 has a
   buzzer instead, so untangling sound-slot playback per board is a real (if
   small) separate task, not a one-line guard change.
6. **Buzzer (GPIO9), KEY_LED (GPIO46), ESP_WAKEUP (GPIO12), MIC/CTRL keys.**
   Pins/keycodes exist; no driver/action references them yet.
7. **Commander (Home tab) landscape layout** — the TX/RX chart and 5-button
   right-hand column (Advert/Terminal/Files/Apps/Control) sizing gates in
   makeHome() didn't include HAS_THINKNODE_M9, so the chart drew full-width over
   the buttons and the last button overflowed off-screen. Fixed.

## Keyboard: register-addressed I2C slave (protocol build #8, USB-pad release build #9)

"No keys do anything" root cause: the keyboard is a separate ESP32-S2 running
Elecrow's matrix-scanner firmware (ThinkNode-M9-KB-platformio, provided by Kaj
2026-07-06) as an I2C slave @0x6C with addressed registers: 0x00 HW ver (0x03),
0x01 KEY VALUE (0x00 = none, single latched slot), 0x02 backlight duty, 0xFE FW
ver (0x10). A key read must WRITE the register address (0x01) first, then read
one byte. The contributed patch's "one raw byte per read" protocol read the
last-addressed register instead — register 0x00 after the controller's reset,
i.e. a constant 0x03, never a key. Driver fixed in M9Keyboard.cpp
(write-then-read + version-register boot probe with serial log + Wire fallback
probe + 1 s re-probe + backlight setter). The controller resolves shift/sym/alt
layers itself and sends final ASCII; long-press codes 0x87 (from 0x84) and 0xA3
(from Enter) exist but are not yet bound in the UI.

Build #8 was still dead. Schematic verification (V1.0 sheet, high-res crops):
keyboard bus host GPIO20 = ESP32-2_SDA / GPIO21 = ESP32-2_SCL (through R2/R1
series, pullups R73/R72, S2 on always-on 3V3) — wiring correct. The real
blocker: GPIO19/20 are the S3's native USB D-/D+ pads, owned from reset by the
ROM's USB-Serial-JTAG peripheral (D+ pullup on GPIO20 = SDA). The M9's console
is an external UART bridge, so nothing ever released them. M9Board::begin() now
clears USB_SERIAL_JTAG_CONF0.USB_PAD_ENABLE before any bus init (build #9).
Bonus schematic finds: SD_CS = GPIO48 (the patch's "36" misread package pin 36 =
SPICLK_N = GPIO48; SD IS on the shared SPI bus), keyboard wake pulse
ESP32_WAKEUP = host GPIO12, KEY_LED = host GPIO46, LCD_TE = GPIO19. If #9 is
still dead, suspect a BLANK keyboard S2 on preprod units - flash it with the
ThinkNode-M9-KB-platformio project via the J6 header (carries ESP32-2
UART/EN/BOOT).

## Radio init -706: old LR1110 transceiver firmware (SOLVED, build #5 — CONFIRMED on hardware)

Tester log 2026-07-06: `Base FW version: 3.3` (0x0303, the original release),
`DriveDiosInSleepMode unsupported (old LR11x0 FW), skipping`,
`LR1110: hw=0x22 device=0x01 fw=3.3 wifi=2.1 gnss=0.0 errors=0x0000`,
`[BOOT] radio ok`, UI up. Build #6 fixed the panel orientation: DISPLAY_ROTATION
3 -> 1 (was 180 deg off). Build #7 fixed the "content a bit left and down":
UITask's per-board s_ui_rotation overrides (T-Deck, Tanmatsu) had no M9 entry,
so LVGL rendered the PORTRAIT default 240x320 into the landscape 320x240 panel
window. Fix = `s_ui_rotation = LV_DISP_ROT_90` under HAS_THINKNODE_M9 (ROT_90 ->
panel rotation 1). Rule of thumb: a new landscape board needs BOTH the
DISPLAY_ROTATION build flag (splash) AND the UITask s_ui_rotation override (LVGL
UI).

The -707 -> -706 progression decoded: -707 (CMD_FAIL) with tcxo=0 was the
calibration failing on a dead 32 MHz clock; with TCXO 3.3 V the calibration
passes and init reaches `driveDiosInSleepMode` (opcode 0x012A, added in Semtech
transceiver FW 0x0308) which RadioLib 7.x sends unconditionally in
`LR11x0::config()`. Preprod M9 chips run older FW and answer CMD_PERR ->
RADIOLIB_ERR_SPI_CMD_INVALID (-706), aborting an otherwise healthy init.
Meshtastic works on the same unit because it pins an older RadioLib that never
sends the command. Fix: `scripts/build/patch_radiolib_lr11x0.py` (extra_script
on the M9 env) makes config() skip that optional command on old FW;
`radio_init()` now prints `LR1110: hw=.. device=.. fw=X.Y ... errors=0x....` in
both outcomes, and the env carries RADIOLIB_DEBUG_BASIC=1 during bring-up. NOT a
shared-SPI problem: PERR is a well-formed chip reply, so the bus is clean.
