local app = {}

local ui = wada.ui
local sys = wada.sys
local store = wada.store

local board = {}
local score = 0
local best = 0

local width = 0
local height = 0

local touchStartX = 0
local touchStartY = 0

local gameOver = false

local CELL = 42
local OFFSET_X = 10
local OFFSET_Y = 40


local function emptyBoard()
    board = {}

    for y = 1,4 do
        board[y] = {}
        for x = 1,4 do
            board[y][x] = 0
        end
    end
end


local function addTile()

    local empty = {}

    for y=1,4 do
        for x=1,4 do
            if board[y][x] == 0 then
                table.insert(empty,{x=x,y=y})
            end
        end
    end

    if #empty == 0 then
        return
    end

    local p = empty[math.random(#empty)]

    if math.random(10) == 1 then
        board[p.y][p.x] = 4
    else
        board[p.y][p.x] = 2
    end
end


local function reset()

    score = 0
    gameOver = false

    emptyBoard()

    addTile()
    addTile()

end


local function compress(line)

    local result = {}

    for i=1,#line do
        if line[i] ~= 0 then
            table.insert(result,line[i])
        end
    end

    return result
end



local function merge(line)

    local result={}
    local i=1

    while i <= #line do

        if line[i] == line[i+1] then

            local v=line[i]*2

            table.insert(result,v)

            score=score+v

            if score > best then
                best=score
                store.set("2048_best",best)
            end

            i=i+2

        else

            table.insert(result,line[i])
            i=i+1

        end
    end


    while #result < 4 do
        table.insert(result,0)
    end

    return result

end



local function moveLeft()

    local changed=false

    for y=1,4 do

        local old={}

        for x=1,4 do
            old[x]=board[y][x]
        end


        local line=compress(old)

        line=merge(line)


        for x=1,4 do
            board[y][x]=line[x]

            if old[x] ~= line[x] then
                changed=true
            end
        end

    end

    return changed
end



local function rotate()

    local n={}

    for y=1,4 do
        n[y]={}
    end


    for y=1,4 do
        for x=1,4 do
            n[x][5-y]=board[y][x]
        end
    end

    board=n
end



local function move(dir)

    local changed=false

    if dir=="left" then

        changed=moveLeft()


    elseif dir=="right" then

        rotate()
        rotate()

        changed=moveLeft()

        rotate()
        rotate()


    elseif dir=="up" then

        rotate()
        rotate()
        rotate()

        changed=moveLeft()

        rotate()


    elseif dir=="down" then

        rotate()

        changed=moveLeft()

        rotate()
        rotate()
        rotate()

    end


    if changed then
        addTile()
    end

end



local function canMove()

    for y=1,4 do
        for x=1,4 do

            if board[y][x]==0 then
                return true
            end

            if x<4 and board[y][x]==board[y][x+1] then
                return true
            end

            if y<4 and board[y][x]==board[y+1][x] then
                return true
            end

        end
    end

    return false

end



local function draw()

    ui.clear()


    ui.text(
        10,
        10,
        "2048  Score: "..score,
        ui.colors.white
    )


    for y=1,4 do

        for x=1,4 do

            local value=board[y][x]

            local px=OFFSET_X+(x-1)*CELL
            local py=OFFSET_Y+(y-1)*CELL


            ui.rect(
                px,
                py,
                CELL-3,
                CELL-3,
                ui.colors.gray
            )


            if value>0 then

                ui.text(
                    px+10,
                    py+10,
                    tostring(value),
                    ui.colors.black
                )

            end

        end

    end



    if gameOver then

        ui.text(
            20,
            230,
            "GAME OVER - tap",
            ui.colors.red
        )

    end


end




function app.on_open(w,h)

    width=w
    height=h

    math.randomseed(sys.time())

    best=store.get("2048_best") or 0

    reset()

end




function app.on_input(ev)


    if ev.type=="touch_down" then

        touchStartX=ev.x
        touchStartY=ev.y

    end



    if ev.type=="touch_up" then

        local dx=ev.x-touchStartX
        local dy=ev.y-touchStartY


        if math.abs(dx)<20 and math.abs(dy)<20 then

            if gameOver then
                reset()
            end

            return
        end


        if math.abs(dx)>math.abs(dy) then

            if dx>0 then
                move("right")
            else
                move("left")
            end

        else

            if dy>0 then
                move("down")
            else
                move("up")
            end

        end


        if not canMove() then
            gameOver=true
        end

    end



    if ev.type=="key" then

        if ev.key=="LEFT" then move("left") end
        if ev.key=="RIGHT" then move("right") end
        if ev.key=="UP" then move("up") end
        if ev.key=="DOWN" then move("down") end

    end


end



function app.on_tick(dt)

    draw()

end



function app.on_close()

end


return app
