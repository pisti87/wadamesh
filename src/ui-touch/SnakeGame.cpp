// SPDX-License-Identifier: GPL-3.0-or-later
#include "SnakeGame.h"

#include <Arduino.h>          // random()
#include <string.h>           // memmove
#include <LvglPsramAlloc.h>   // PSRAM-preferred buffer for the canvas

// Mirrors the app's status-bar height; the overlay starts below it so the bar
// stays visible. Kept local so this module needs nothing from UITask.
static constexpr lv_coord_t kTopBar = 22;

// Palette (hex literals so the module is self-contained).
static constexpr uint32_t kColBg     = 0x0A0B0C;   // playfield background
static constexpr uint32_t kColFood   = 0xE0584C;   // food
static constexpr uint32_t kColBody   = 0x15B6A6;   // snake body (brand teal)
static constexpr uint32_t kColHead   = 0x15B6A6;   // head (same hue; brighter via the head check)
static constexpr uint32_t kColText   = 0xE6EAEE;

SnakeGame* SnakeGame::s_active = nullptr;

void SnakeGame::launch() {
  if (s_active) return;                 // already running
  SnakeGame* g = new SnakeGame();
  s_active = g;
  if (!g->open()) {                     // alloc failed — clean up, no overlay
    s_active = nullptr;
    delete g;
  }
}

void SnakeGame::placeFood() {
  for (int tries = 0; tries < 400; ++tries) {
    const uint8_t fx = (uint8_t)random(kGrid);
    const uint8_t fy = (uint8_t)random(kGrid);
    bool on = false;
    for (int i = 0; i < len_; ++i) if (bx_[i] == fx && by_[i] == fy) { on = true; break; }
    if (!on) { fx_ = fx; fy_ = fy; return; }
  }
}

void SnakeGame::reset() {
  len_ = 3;
  for (int i = 0; i < len_; ++i) { bx_[i] = (uint8_t)(kGrid / 2 - i); by_[i] = kGrid / 2; }
  dx_ = 1; dy_ = 0; ndx_ = 1; ndy_ = 0;
  over_ = false; score_val_ = 0;
  placeFood();
}

void SnakeGame::render() {
  if (!canvas_) return;
  const int c = cell_;
  lv_canvas_fill_bg(canvas_, lv_color_hex(kColBg), LV_OPA_COVER);
  lv_draw_rect_dsc_t d; lv_draw_rect_dsc_init(&d); d.radius = 2;
  d.bg_color = lv_color_hex(kColFood);
  lv_canvas_draw_rect(canvas_, fx_ * c + 1, fy_ * c + 1, c - 2, c - 2, &d);
  for (int i = 0; i < len_; ++i) {
    d.bg_color = (i == 0) ? lv_color_hex(kColHead) : lv_color_hex(kColBody);
    d.bg_opa   = (i == 0) ? LV_OPA_COVER : LV_OPA_80;   // head reads brighter
    lv_canvas_draw_rect(canvas_, bx_[i] * c + 1, by_[i] * c + 1, c - 2, c - 2, &d);
  }
}

void SnakeGame::updateScoreLabel() {
  if (!score_) return;
  if (over_) lv_label_set_text_fmt(score_, "Game over  \xe2\x80\x94  score %d   (tap to restart)", score_val_);
  else       lv_label_set_text_fmt(score_, "score %d", score_val_);
}

void SnakeGame::step() {
  if (over_) return;
  if (!(ndx_ == -dx_ && ndy_ == -dy_)) { dx_ = ndx_; dy_ = ndy_; }
  const int nx = bx_[0] + dx_, ny = by_[0] + dy_;
  const bool eat = (nx == fx_ && ny == fy_);
  bool over = (nx < 0 || ny < 0 || nx >= kGrid || ny >= kGrid);
  const int clen = eat ? len_ : len_ - 1;   // the tail vacates unless we grow
  for (int i = 0; i < clen && !over; ++i) if (bx_[i] == nx && by_[i] == ny) over = true;
  if (over) { over_ = true; updateScoreLabel(); return; }

  int newlen = len_ + (eat ? 1 : 0);
  if (newlen > kGrid * kGrid) newlen = kGrid * kGrid;
  memmove(&bx_[1], &bx_[0], (size_t)(newlen - 1));
  memmove(&by_[1], &by_[0], (size_t)(newlen - 1));
  bx_[0] = (uint8_t)nx; by_[0] = (uint8_t)ny;
  len_ = newlen;
  if (eat) { score_val_++; placeFood(); updateScoreLabel(); }
  render();
}

void SnakeGame::setDir(int dx, int dy) { ndx_ = dx; ndy_ = dy; }

bool SnakeGame::open() {
  const lv_coord_t sw = lv_disp_get_hor_res(nullptr);
  const lv_coord_t sh = lv_disp_get_ver_res(nullptr);
  root_ = lv_obj_create(lv_layer_top());
  lv_obj_remove_style_all(root_);
  lv_obj_set_size(root_, sw, sh - kTopBar);
  lv_obj_set_pos(root_, 0, kTopBar);
  lv_obj_set_style_bg_color(root_, lv_color_hex(0x0E1216), LV_PART_MAIN);
  lv_obj_set_style_bg_opa(root_, LV_OPA_COVER, LV_PART_MAIN);
  lv_obj_clear_flag(root_, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(root_, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(root_, gestureCb, LV_EVENT_GESTURE, this);
  lv_obj_add_event_cb(root_, tapCb,     LV_EVENT_CLICKED, this);

  // Largest square playfield that fits below a 26-px score/close row.
  const int avail_h = (int)(sh - kTopBar) - 28;
  int side = ((int)sw < avail_h) ? (int)sw : avail_h;
  cell_ = side / kGrid;
  if (cell_ < 6) cell_ = 6;
  const int canvas_px = cell_ * kGrid;
  buf_ = (lv_color_t*)lvglPsramAlloc((size_t)canvas_px * canvas_px * sizeof(lv_color_t));
  if (!buf_) return false;              // caller frees the half-built instance
  canvas_ = lv_canvas_create(root_);
  lv_canvas_set_buffer(canvas_, buf_, canvas_px, canvas_px, LV_IMG_CF_TRUE_COLOR);
  lv_obj_align(canvas_, LV_ALIGN_TOP_MID, 0, 26);

  score_ = lv_label_create(root_);
  lv_obj_set_style_text_color(score_, lv_color_hex(kColText), LV_PART_MAIN);
  lv_obj_align(score_, LV_ALIGN_TOP_LEFT, 6, 4);

  lv_obj_t* x = lv_btn_create(root_);
  lv_obj_set_size(x, 30, 24);
  lv_obj_align(x, LV_ALIGN_TOP_RIGHT, -4, 0);
  lv_obj_add_event_cb(x, closeCb, LV_EVENT_CLICKED, this);
  lv_obj_t* xl = lv_label_create(x); lv_label_set_text(xl, LV_SYMBOL_CLOSE); lv_obj_center(xl);

  reset();
  lv_label_set_text_fmt(score_, "score %d   (swipe to steer)", score_val_);
  render();
  timer_ = lv_timer_create(timerCb, 220, this);   // 220 ms / step
  return true;
}

void SnakeGame::close() {
  if (timer_) { lv_timer_del(timer_); timer_ = nullptr; }
  if (root_)  { lv_obj_del(root_);   root_  = nullptr; }   // deletes the canvas child
  if (buf_)   { lvglPsramFree(buf_);  buf_  = nullptr; }   // free AFTER the canvas is gone
  canvas_ = nullptr; score_ = nullptr;
}

// ---- LVGL C-callback trampolines (user_data = the instance) ----
void SnakeGame::timerCb(lv_timer_t* t) {
  auto* self = static_cast<SnakeGame*>(t->user_data);
  if (self) self->step();
}
void SnakeGame::gestureCb(lv_event_t* e) {
  auto* self = static_cast<SnakeGame*>(lv_event_get_user_data(e));
  if (!self) return;
  switch (lv_indev_get_gesture_dir(lv_indev_get_act())) {
    case LV_DIR_TOP:    self->setDir(0, -1); break;
    case LV_DIR_BOTTOM: self->setDir(0, 1);  break;
    case LV_DIR_LEFT:   self->setDir(-1, 0); break;
    case LV_DIR_RIGHT:  self->setDir(1, 0);  break;
    default: break;
  }
}
void SnakeGame::tapCb(lv_event_t* e) {
  auto* self = static_cast<SnakeGame*>(lv_event_get_user_data(e));
  if (self && self->over_) { self->reset(); self->updateScoreLabel(); self->render(); }
}
void SnakeGame::closeCb(lv_event_t* e) {
  auto* self = static_cast<SnakeGame*>(lv_event_get_user_data(e));
  if (!self) return;
  self->close();
  if (s_active == self) s_active = nullptr;
  delete self;
}
