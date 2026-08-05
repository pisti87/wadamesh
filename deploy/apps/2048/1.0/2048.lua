-- 2048 — wada.* reference app
-- Swipe (or trackball mapped swipe) to move tiles.
-- Tap after game over to restart.

local ui, sys, store, timer = wada.ui, wada.sys, wada.store, wada.timer
local C = ui.colors

local app = {}

local cv, score_lbl

local CELL = 38

local grid = {}
local history = {
  grids = {},
  maxsize = 5
}

local px_w, px_h
local score = 0
local hiscore = 0
local over = false

--------------------------------------------------
-- History
--------------------------------------------------

function history:save()
  local old = {}

  for x = 1,4 do
    old[x] = {}
    for y = 1,4 do
      old[x][y] = grid[x][y]
    end
  end

  table.insert(self.grids, old)

  if #self.grids > self.maxsize then
    table.remove(self.grids,1)
  end
end


function history:revert()
  if #self.grids > 0 then
    grid = table.remove(self.grids)
  end
end


--------------------------------------------------
-- Game logic
--------------------------------------------------

local function clear_grid()

  grid = {}

  for x=1,4 do
    grid[x]={}
    for y=1,4 do
      grid[x][y]=0
    end
  end

end


local function add_random_tile()

  local free={}

  for x=1,4 do
    for y=1,4 do
      if grid[x][y]==0 then
        table.insert(free,{x=x,y=y})
      end
    end
  end


  if #free==0 then
    return
  end


  local p=free[sys.random(1,#free)]

  if sys.random(0,9)==0 then
    grid[p.x][p.y]=4
  else
    grid[p.x][p.y]=2
  end

end



local function reset()

  clear_grid()

  score=0
  over=false

  history.grids={}

  add_random_tile()
  add_random_tile()

end



local function compress(line)

  local r={}

  for i=1,4 do
    if line[i]~=0 then
      table.insert(r,line[i])
    end
  end

  while #r<4 do
    table.insert(r,0)
  end

  return r

end



local function merge(line)

  local r={}
  local i=1

  while i<=4 do

    if line[i]~=0 and line[i]==line[i+1] then

      local v=line[i]*2

      table.insert(r,v)

      score=score+v

      if score>hiscore then
        hiscore=score
        store.set("2048_best",hiscore)
      end

      i=i+2

    else

      table.insert(r,line[i])
      i=i+1

    end

  end


  while #r<4 do
    table.insert(r,0)
  end


  return r

end



local function move_left()

  local changed=false


  for y=1,4 do

    local old={}
    local line={}

    for x=1,4 do
      old[x]=grid[x][y]
      line[x]=grid[x][y]
    end


    line=compress(line)
    line=merge(line)


    for x=1,4 do
      grid[x][y]=line[x]

      if old[x]~=line[x] then
        changed=true
      end
    end

  end


  return changed

end



local function rotate()

  local n={}

  for x=1,4 do
    n[x]={}
  end


  for x=1,4 do
    for y=1,4 do
      n[y][5-x]=grid[x][y]
    end
  end


  grid=n

end



local function move(dir)

  history:save()

  local changed=false


  if dir=="left" then

    changed=move_left()


  elseif dir=="right" then

    rotate()
    rotate()

    changed=move_left()

    rotate()
    rotate()


  elseif dir=="up" then

    rotate()
    rotate()
    rotate()

    changed=move_left()

    rotate()


  elseif dir=="down" then

    rotate()

    changed=move_left()

    rotate()
    rotate()
    rotate()

  end


  if changed then
    add_random_tile()
  else
    history:revert()
  end

end



local function game_over()

  for x=1,4 do
    for y=1,4 do

      if grid[x][y]==0 then
        return false
      end

      if x<4 and grid[x][y]==grid[x+1][y] then
        return false
      end

      if y<4 and grid[x][y]==grid[x][y+1] then
        return false
      end

    end
  end


  return true

end


--------------------------------------------------
-- Drawing
--------------------------------------------------

local function scoreline()

  score_lbl:set(
    string.format(
      "Score %d   Best %d%s",
      score,
      hiscore,
      over and "   - tap retry" or ""
    )
  )

end



local function draw()

  cv:fill(0x101418)


  for x=1,4 do
    for y=1,4 do

      local px=(x-1)*CELL
      local py=(y-1)*CELL

      cv:rect(
        px+2,
        py+2,
        CELL-4,
        CELL-4,
        C.good,
        true,
        4
      )


      local v=grid[x][y]

      if v>0 then

        cv:text(
          px+10,
          py+10,
          tostring(v),
          C.text,
          16
        )

      end

    end
  end


  if over then
    cv:text(
      30,
      px_h/2,
      "GAME OVER",
      C.bad,
      18
    )
  end

end



--------------------------------------------------
-- WADAMESH API
--------------------------------------------------

function app.on_open(w,h)

  hiscore=store.get("2048_best",0)

  px_w=CELL*4
  px_h=CELL*4


  score_lbl=ui.label(
    "",
    4,
    4,
    14,
    C.text
  )


  cv=ui.canvas(px_w,px_h)

  cv:pos(
    math.floor((w-px_w)/2),
    28
  )


  reset()

  scoreline()
  draw()

  timer.every(100)

end



function app.on_input(ev)


  if ev.type=="swipe" then

    move(ev.dir)


    if game_over() then
      over=true
    end


    scoreline()
    draw()


  elseif ev.type=="down" and over then

    reset()

    scoreline()
    draw()

  end

end



function app.on_tick(dt)

end



function app.on_close()

end


return app
