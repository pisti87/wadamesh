// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <lvgl.h>

// Self-contained Snake mini-game launched from the Apps drawer.
//
// Owns a full-screen overlay on lv_layer_top: a square canvas playfield, a score
// line, and a close button. Swipe up/down/left/right to steer, tap to restart
// after a game over, the X to close. One instance lives at a time (a static
// singleton); launch() is a no-op while it's already open.
//
// Deliberately decoupled from UITask internals — it depends only on LVGL and the
// shared lvglPsramAlloc helpers, so it can live in its own translation unit.
class SnakeGame {
public:
  // Open the game (creates the overlay + starts the tick). No-op if already open.
  static void launch();

private:
  static constexpr int kGrid = 14;   // cells per side

  lv_obj_t*   root_   = nullptr;     // full-screen overlay (owns everything below)
  lv_obj_t*   canvas_ = nullptr;
  lv_color_t* buf_    = nullptr;     // canvas pixel buffer (PSRAM)
  lv_obj_t*   score_  = nullptr;
  lv_timer_t* timer_  = nullptr;

  int     cell_ = 13;                // px per cell (set at open)
  uint8_t bx_[kGrid * kGrid];        // snake body, [0] = head
  uint8_t by_[kGrid * kGrid];
  int     len_ = 0;
  int     dx_ = 1, dy_ = 0;          // active direction
  int     ndx_ = 1, ndy_ = 0;       // queued direction (applied next step)
  uint8_t fx_ = 0, fy_ = 0;          // food cell
  bool    over_ = false;
  int     score_val_ = 0;

  bool open();                       // build UI + start; false on alloc failure
  void close();                      // stop tick + free + delete overlay
  void reset();
  void placeFood();
  void render();
  void step();
  void setDir(int dx, int dy);
  void updateScoreLabel();

  static SnakeGame* s_active;        // the one live game (or nullptr)
  static void timerCb(lv_timer_t* t);
  static void gestureCb(lv_event_t* e);
  static void tapCb(lv_event_t* e);
  static void closeCb(lv_event_t* e);
};
