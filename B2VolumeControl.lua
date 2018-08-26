require "graphics"

-- B2VolumeControl.lua
--   To be used in conjunction with X-Plane's FlyWithLua scripting package
--   Developed using FlyWithLua Complete v2.6.7
-- 
--   Place B2VolumeControl.lua in your FlyWithLua scripts folder
--      path:    ...\X-Plane 11\Resources\plugins\FlyWithLua\Scripts\
--
--   ** This script will allow you to adjust the X-Plane11 sound sliders without going
--          into the settings menu and without needing to pause the simulator.  
--   ** To customize the location of the widget for your personal use, you may easily
--          do so in the B2VolumeControl_LocationInitialization() function below
--
--   To activate :: move your mouse to upper right corner of the screen
--                      and click on the magically appearing 'sound icon'
--   To adjust   :: use your mouse wheel to change the value of the given 'knob'
--   To hide     :: just click the 'sound icon' again and it'll hide the knobs from view
--
--   NOTE:  some 'knobs' adjust the volume of sounds that don't seem related, but this should
--              be identical functionality to using the X-Plane settings sliders 
--   NOTE:  some aircraft may 'compete' with this script, not allowing the values to change
--              as desired, so if you roll your mouse wheel while over a 'knob' and nothing
--              happens, that is probably why
--
--   Initial version:   Aug 2018    B2_
--
-- Copyright 2018 'b2videogames at gmail dot com'
--  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
--  associated documentation files (the "Software"), to deal in the Software without restriction,
--  including without limitation the rights to use, copy, modify, merge, publish, distribute,
--  sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
--  furnished to do so, subject to the following conditions:
-- 
--  The above copyright notice and this permission notice shall be included in all copies or substantial
--  portions of the Software.
-- 
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
--  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
--  OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
--  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local b2vc_SoftwareVersion = 2
local b2vc_FileFormat = 1


dataref("b2vc_mastervolume", "sim/operation/sound/master_volume_ratio", "writable")
dataref("b2vc_exteriorVolume", "sim/operation/sound/exterior_volume_ratio", "writable")
dataref("b2vc_interiorVolume", "sim/operation/sound/interior_volume_ratio", "writable")
dataref("b2vc_copilotVolume", "sim/operation/sound/copilot_volume_ratio", "writable")
dataref("b2vc_radioVolume", "sim/operation/sound/radio_volume_ratio", "writable")
dataref("b2vc_enviroVolume", "sim/operation/sound/enviro_volume_ratio", "writable")
dataref("b2vc_uiVolume", "sim/operation/sound/ui_volume_ratio", "writable")

dataref("b2vc_viewExternal", "sim/graphics/view/view_is_external")


local mainX = SCREEN_WIDTH - 10  -- default position, to change use B2VolumeControl_LocationInitialization()
local mainY = SCREEN_HIGHT - 40  -- default position, to change use B2VolumeControl_LocationInitialization()
local prevX = mainX
local prevY = mainY
local prevView = b2vc_viewExternal
local bDrawControlBox = false
local bScreenSizeChanged = true
local bFirstDraw = true
local bSaveRequired = false
local knobRadius = 20
local fixedGap = 5
local topBoxY = mainY - (4*fixedGap)
local fixedTextSpace = 60
local bDragging = false
local bAutoPosition = true
local initialTest = 1

-- knobs[knobX,knobY,nameOfKnob,textX,knobInt,knobExt]
local numKnobs = 7  -- total count of Volume datarefs
local knobX = 1
local knobY = 2
local knobName = 3
local knobTextX = 4
local knobInt = 5   -- Volume used for both if knobExt -1
local knobExt = 6   -- value of -2 is 'failed' set test
local knobs = { {0, 0, "master",   0, b2vc_mastervolume,   -1},
                {0, 0, "exterior", 0, b2vc_exteriorVolume, -1},
                {0, 0, "interior", 0, b2vc_interiorVolume, -1},
                {0, 0, "copilot",  0, b2vc_copilotVolume,  -1},
                {0, 0, "radio",    0, b2vc_radioVolume,    -1},
                {0, 0, "enviro",   0, b2vc_enviroVolume,   -1},
                {0, 0, "ui",       0, b2vc_uiVolume,       -1} }
local i  -- just for local iterations

do_often("B2VolumeControl_everySec()")
do_every_draw("B2VolumeControl_everyDraw()")
do_every_frame("B2VolumeControl_everyFrame()")
do_on_mouse_click("B2VolumeControl_mouseClick()")
do_on_mouse_wheel("B2VolumeControl_onMouseWheel()")

-- **************************************************************************************
--   To customize the location of the widget, simply modify the mainX and mainY coordinates here
--   as all other values are based on that location.
--       (mainX,mainY) is the coordinate of a pixel which is located at the middle, right most
--                     position of the 'active sound icon'
--
--   note: positions relative to the bottom or left edge of screen should be a 'fixed' value
--   note: positions relative to the top or right edge of screen should be a 'variable' value
--   example:   (125,SCREEN_HIGHT-40) would be positioned 125 pixels to the right of the left edge
--              and SCREEN_HIGHT-40 pixels from the top edge :: as the screen gets taller/shorter,
--              the value of SCREEN_HIGHT will change, keeping the widget where you wanted it
--
--      x ::  0 is left edge of screen, SCREEN_WIDTH is right edge of screen
--      y ::  0 is bottom edge of screen, SCREEN_HIGHT is top edge of screen
--          
--      default: 10 pixels from right edge of screen, 40 pixels from top edge of screen
-- **************************************************************************************
function B2VolumeControl_LocationInitialization()
    mainX = SCREEN_WIDTH - 10
    mainY = SCREEN_HIGHT - 40
end

function B2VolumeControl_everySec()
    if (bAutoPosition == true) then
        -- handle screen width changes
        local prevmainX = mainX
        local prevmainY = mainY
        B2VolumeControl_LocationInitialization()
        if (not(prevmainX == mainX and prevmainY == mainY)) then
            bScreenSizeChanged = true
        end
    end
end

function B2VolumeControl_everyFrame()
    -- USE THIS ROUTINE SPARINGLY
    local testValue = 0.03125 -- a good 'binary' random number
    if (initialTest == 1) then                                  -- stage 1 of test
        for i = 1,numKnobs do
            knobs[i][knobExt] = B2VolumeControl_GetVolume(i)    -- store original Value 
            B2VolumeControl_SetVolume(i,testValue)              -- set a random number to see if it takes
        end
        initialTest = 2                                         -- ready for stage 2 of test
        return
    elseif (initialTest == 2) then
        for i = 1,numKnobs do
            local testResult = B2VolumeControl_GetVolume(i)
            if (testResult == testValue) then                   -- check against test number
                testResult = -1                                 -- test passed
            else
                testResult = -2                                 -- test Failed
            end
            B2VolumeControl_SetVolume(i,knobs[i][knobExt])      -- return to original value
            knobs[i][knobExt] = testResult
        end
        initialTest = 3                                         -- ready for stage 3, loading config
    elseif (initialTest == 3) then
        B2VolumeControl_OpenParseConfig()
        initialTest = 0                                         -- done startup initialization
    end

    if not(prevView == b2vc_viewExternal) then --internal/external view swap, change volumes if necessary
        for i = 1,numKnobs do
            if (knobs[i][knobExt] >= 0) then
                if (b2vc_viewExternal == 0) then    -- internal view
                    B2VolumeControl_SetVolume(i,knobs[i][knobInt])
                else                                -- external view
                    B2VolumeControl_SetVolume(i,knobs[i][knobExt])
                end
            end
        end
        prevView = b2vc_viewExternal
        bFirstDraw = true
    end
end

function B2VolumeControl_everyDraw()
    -- OpenGL graphics state initialization
    XPLMSetGraphicsState(0,0,0,1,1,0,0)                     -- use only in do_every_draw()

    if (bDrawControlBox == true or
        (MOUSE_X >= (mainX-100) and MOUSE_X <= (mainX+100) and 
         MOUSE_Y >= (mainY-100) and MOUSE_Y <= (mainY+100))) then

        -- always draw clickable sound icon
        graphics.set_color(0,0,0,1) -- black
        graphics.draw_rectangle(mainX-40,mainY-8,mainX-20,mainY+8)
        graphics.draw_triangle(mainX-40,mainY,mainX-20,mainY+15,mainX-20,mainY-15)

        graphics.set_color(0.4,0.4,0.4,1) -- gray
        graphics.draw_rectangle(mainX-39,mainY-7,mainX-21,mainY+7)
        graphics.draw_triangle(mainX-37,mainY,mainX-21,mainY+13,mainX-21,mainY-13)

        if (bDrawControlBox == true) then
            -- draw 'drag' wheel
            graphics.set_color(1,1,1,0.5) -- white border
            graphics.draw_filled_circle(mainX-85,mainY,5)
            graphics.set_color(140/255,128/255,99/255,0.8) -- fill in color
            graphics.draw_filled_circle(mainX-85,mainY,4)

            -- draw 'save' icon
            if (bSaveRequired == true) then
                graphics.set_color(1,0,0,0.5) -- red border
            else
                graphics.set_color(0,1,0,0.5) -- green border
            end
            graphics.draw_triangle(mainX-60,mainY-3,mainX-67,mainY+7,mainX-53,mainY+7)
            graphics.draw_line(mainX-69,mainY-1,mainX-69,mainY-9)
            graphics.draw_line(mainX-69,mainY-9,mainX-51,mainY-9)
            graphics.draw_line(mainX-51,mainY-9,mainX-51,mainY-1)
            graphics.set_color(0,0,0,0.5) -- fill in color
            graphics.draw_triangle(mainX-60,mainY,mainX-65,mainY+6,mainX-55,mainY+6)
            graphics.draw_line(mainX-68,mainY-1,mainX-68,mainY-8)
            graphics.draw_line(mainX-68,mainY-8,mainX-52,mainY-8)
            graphics.draw_line(mainX-52,mainY-8,mainX-52,mainY-1)

            -- draw 'active' sound icon
            graphics.set_color(140/255,128/255,99/255,1) -- fill in color
            graphics.draw_rectangle(mainX-38,mainY-6,mainX-22,mainY+6)
            graphics.draw_triangle(mainX-34,mainY,mainX-22,mainY+11,mainX-21,mainY-11)

            graphics.set_color(173/255,31/255,31/255,1) -- red
            graphics.draw_line(mainX-15,mainY+5,mainX-4,mainY+10)
            graphics.draw_line(mainX-15,mainY,mainX,mainY)
            graphics.draw_line(mainX-15,mainY-5,mainX-4,mainY-10)

            -- recompute workspace / knobs if needed
            if (bScreenSizeChanged == true) then
                topBoxY = mainY - (4*fixedGap)
                B2VolumeControl_computeKnobLocation()
            end

            -- draw background workspace box
            graphics.set_color(66/255, 66/255, 66/255, 1) -- dark gray
            local x2 = mainX
            local x1 = x2 - (2*knobRadius) - fixedTextSpace
            local y1 = topBoxY
            local y2 = y1 - (numKnobs*(knobRadius*2)) - ((numKnobs)*fixedGap)
            graphics.draw_rectangle(x1,y1,x2,y2)

            graphics.set_color(45/255,150/255,10/255,1) -- green
            for i = 1,numKnobs do
                B2VolumeControl_drawKnob(i)
            end
        bFirstDraw = false
        end -- box drawn
    end -- mouse near click spot
end

function B2VolumeControl_mouseClick()
    if (MOUSE_STATUS == "up") then bDragging = false end

    if (MOUSE_STATUS == "down" and bDrawControlBox == true) then
        for i = 1,numKnobs do
            if (MOUSE_X >= (knobs[i][knobX]-knobRadius-fixedTextSpace) and MOUSE_X <= (knobs[i][knobX]+knobRadius) and
                MOUSE_Y >= (knobs[i][knobY]-knobRadius) and MOUSE_Y <= (knobs[i][knobY]+knobRadius)) then
                RESUME_MOUSE_CLICK = true
                if not(knobs[i][knobExt] == -2) then bSaveRequired = true end   -- unchangeable knob

                if (knobs[i][knobExt] == -1) then
                    -- toggle Inner/Outer enabled by setting knobExt to current shared value
                    knobs[i][knobExt] = knobs[i][knobInt]
                elseif (knobs[i][knobExt] >= 0) then
                    -- toggle Inner/Outer disabled by setting knobExt to -1
                    if (b2vc_viewExternal == 0) then    -- internal view
                        knobs[i][knobExt] = -1
                    else                                -- external view
                        knobs[i][knobInt] = knobs[i][knobExt]
                        knobs[i][knobExt] = -1
                    end
                end
                return
            end
        end
    end

    -- check if position over our toggle icon
    if (MOUSE_STATUS == "down" and 
        MOUSE_X >= (mainX-40) and MOUSE_X <= mainX and 
        MOUSE_Y >= (mainY-15) and MOUSE_Y <= (mainY+15)) then
        RESUME_MOUSE_CLICK = true

        if (bDrawControlBox == true) then
            bDrawControlBox = false
        else 
            bDrawControlBox = true  -- draw the box
        end
    end

    -- check if position over our save icon
    if (MOUSE_STATUS == "down" and 
        MOUSE_X >= (mainX-69) and MOUSE_X <= (mainX-51) and 
        MOUSE_Y >= (mainY-9) and MOUSE_Y <= (mainY+7)) then
        B2VolumeControl_SaveModifiedConfig()
    end

    -- check if position over our drag icon
    if (MOUSE_STATUS == "down" and 
        MOUSE_X >= (mainX-85-5) and MOUSE_X <= (mainX-85+5) and 
        MOUSE_Y >= (mainY-5) and MOUSE_Y <= (mainY+5)) then
        bDragging = true
        RESUME_MOUSE_CLICK = true
    elseif (bDragging == true and MOUSE_STATUS == "drag") then
        mainX = MOUSE_X + 85
        mainY = MOUSE_Y
        bAutoPosition = false
        bSaveRequired = true
    end
end

function B2VolumeControl_onMouseWheel()
    -- mouse wheel only important if knobs visible
    if (bDrawControlBox == false) then
        return
    end

    for i = 1,numKnobs do
        if (MOUSE_X >= (knobs[i][knobX]-knobRadius-fixedTextSpace) and MOUSE_X <= (knobs[i][knobX]+knobRadius) and
            MOUSE_Y >= (knobs[i][knobY]-knobRadius) and MOUSE_Y <= (knobs[i][knobY]+knobRadius)) then
            B2VolumeControl_SetVolume(i,B2VolumeControl_GetVolume(i)+(MOUSE_WHEEL_CLICKS*0.02))
            if not(knobs[i][knobExt] == -2) then bSaveRequired = true end   -- unchangeable knob
            RESUME_MOUSE_WHEEL = true
            return
        end
    end
end

function B2VolumeControl_drawKnob(i)
    local x = knobs[i][knobX]
    local y = knobs[i][knobY]

    if (prevView == b2vc_viewExternal) then  -- don't update data if view is changing
        -- before drawing the arcs, make sure the data we have is up to date
        if (knobs[i][knobExt] < 0 or b2vc_viewExternal == 0) then   -- for single mark or interior view
            if not(knobs[i][knobInt] == B2VolumeControl_GetVolume(i)) then
                if (bFirstDraw == false and not(knobs[i][knobExt] == -2)) then bFirstDraw = true bSaveRequired = true end
            end
            knobs[i][knobInt] = B2VolumeControl_GetVolume(i)
        else                                                        -- for external view
            if not(knobs[i][knobExt] == B2VolumeControl_GetVolume(i)) then
                if (bFirstDraw == false) then bFirstDraw = true bSaveRequired = true end
            end
            knobs[i][knobExt] = B2VolumeControl_GetVolume(i)
        end
    end

    -- x,y are center of knob with knobRadius, volume(s) are between (0.0 - 1.0)
    -- arcs 210-150 (300 degrees) so ((volume * 300)+210)%360 = angle of pointer

    graphics.set_color(0,0,0,1) -- black border
    graphics.draw_arc(x,y,210,360,knobRadius,1)
    graphics.draw_arc(x,y,0,150,knobRadius,1)
    graphics.set_color(140/255,128/255,99/255,1) -- fill knob top color
    graphics.draw_filled_arc(x,y,210,360,19)
    graphics.draw_filled_arc(x,y,0,150,19)

    if (knobs[i][knobExt] == -2) then               -- can't change, draw all black, thin
        graphics.set_color(0,0,0,1)                 -- black
        graphics.draw_angle_arrow(x,y,((knobs[i][knobInt]*300)+210)%360,knobRadius-1,knobRadius/2,1)
    elseif (knobs[i][knobExt] == -1) then           -- shared value, draw pointer
        graphics.set_color(173/255,31/255,31/255,1) -- a nice red
        graphics.draw_angle_arrow(x,y,((knobs[i][knobInt]*300)+210)%360,knobRadius-1,knobRadius/2,2)
    elseif (b2vc_viewExternal == 0) then            -- current view is internal
        graphics.set_color(173/255,31/255,31/255,1) -- a nice red
        graphics.draw_tick_mark(x,y,((knobs[i][knobInt]*300)+210)%360,(knobRadius-1)/2,(knobRadius-1)/2,3)  -- inner tick
        graphics.set_color(0,0,0,1)                 -- black
        graphics.draw_tick_mark(x,y,((knobs[i][knobExt]*300)+210)%360,knobRadius-1,(knobRadius-1)/2,3)      -- outer tick
    else                                            -- current view is external
        graphics.set_color(0,0,0,1)                 -- black
        graphics.draw_tick_mark(x,y,((knobs[i][knobInt]*300)+210)%360,(knobRadius-1)/2,(knobRadius-1)/2,3)  -- inner tick
        graphics.set_color(173/255,31/255,31/255,1) -- a nice red
        graphics.draw_tick_mark(x,y,((knobs[i][knobExt]*300)+210)%360,knobRadius-1,(knobRadius-1)/2,3)      -- outer tick
    end

    draw_string(knobs[i][knobTextX],y,knobs[i][knobName],239/255,219/255,172/255)
end

function B2VolumeControl_computeKnobLocation()
    local y = topBoxY - knobRadius
    local textX = mainX - (2*knobRadius) - fixedTextSpace + 3   -- the '+3' just makes it look nicer
    for i = 1,numKnobs do
        knobs[i][knobX] = mainX - knobRadius - 2                -- '-2' just to look nicer
        knobs[i][knobY] = y - 1                                 -- '-1' just to look nicer
        knobs[i][knobTextX] = textX
        y = y - fixedGap - (2*knobRadius)  -- change 'y' for next knob
    end
end

function B2VolumeControl_OpenParseConfig()
    local configFile = io.open(SCRIPT_DIRECTORY .. "B2VolumeControl.dat","r")
    if not(configFile) then             -- if no config file, just return now
        return
    end

    local tmpStr = configFile:read("*all")
    configFile:close()

    local fileVersion = nil
    local fileX = nil
    local fileY = nil
    local fileName = nil
    
    for i in string.gfind(tmpStr,"%s*(.-)\n") do
        if (fileVersion == nil) then _,_,fileVersion = string.find(i, "VERSION%s+(%d+)") end
        if (fileX == nil and fileY == nil) then 
            _,_,fileX,fileY = string.find(i, "X:%s*(%d+)%s+Y:%s*(%d+)")
            if (fileX and fileY) then
                fileX = tonumber(fileX)
                fileY = tonumber(fileY)
                if (fileX and fileX >= 0 and fileX <= SCREEN_WIDTH and
                    fileY and fileY >= 0 and fileY <= SCREEN_HIGHT) then
                    mainX = fileX
                    mainY = fileY
                    bAutoPosition = false
                    bScreenSizeChanged = true
                end
            end
        end
        if (fileName == nil) then
            local _,_,lFileName,lData = string.find(i, "^(.+%.acf)[%s+](.+)")
            if (lFileName and lFileName == AIRCRAFT_FILENAME) then
                if (lFileName == AIRCRAFT_FILENAME) then
                    fileName = lFileName
                    local knobNum = 1
                    for lInt,lExt in string.gfind(lData,"%s-(%d%.%d+)%s+(%-?%d%.%d+)") do 
                        knobs[knobNum][knobInt] = tonumber(lInt)
                        knobs[knobNum][knobExt] = tonumber(lExt)
                        if (b2vc_viewExternal == 0) then
                            B2VolumeControl_SetVolume(knobNum,knobs[knobNum][knobInt])
                        else
                            B2VolumeControl_SetVolume(knobNum,knobs[knobNum][knobExt])
                        end
                        knobNum = knobNum + 1
                    end
                end
            end
        end
    end
    bSaveRequired = false
end

function B2VolumeControl_SaveModifiedConfig()
    local oldStr = nil  -- where we'll store all the data from the previous config file
    local newStr = nil  -- where we'll store all the data to write to the config file

    local configFile = io.open(SCRIPT_DIRECTORY .. "B2VolumeControl.dat","r")
    if (configFile) then
        oldStr = configFile:read("*all")
        configFile:close()
    end

    -- store file format version
    newStr = string.format("VERSION " .. b2vc_FileFormat .. "\n")

    -- if user moved the widget manually, store where they want it
    if not(bAutoPosition) then
        newStr = string.format(newStr .. "X:" .. mainX .. " Y:" .. mainY .. "\n")
    end

    -- store the current config data for loaded acf
    newStr = string.format(newStr .. AIRCRAFT_FILENAME)
    for i = 1,numKnobs do
        newStr = string.format("%s %f %f",newStr,knobs[i][knobInt],knobs[i][knobExt])
    end
    newStr = string.format(newStr .. "\n")

    -- if oldStr, we need to duplicate all the acf data that isn't our current acf
    if (oldStr) then
        for i in string.gfind(oldStr,"%s*(.-)\n") do
            -- look at each line for an acf file entry, then, if that
            -- entry doesn't match the loaded acf write its data
            local start,_,lFileName,lData = string.find(i, "^(.+%.acf)[%s+](.+)$")
            if (start and not(lFileName == AIRCRAFT_FILENAME)) then
                newStr = string.format(newStr .. i .. "\n")
            end
        end
    end

    local configFile = io.open(SCRIPT_DIRECTORY .. "B2VolumeControl.dat","w")
    if not(configFile) then return end      -- error handled
    io.output(configFile)
    io.write(newStr)
    configFile:close()
    bSaveRequired = false
end

function B2VolumeControl_GetVolume(i)
    if (i == 1) then return b2vc_mastervolume end
    if (i == 2) then return b2vc_exteriorVolume end
    if (i == 3) then return b2vc_interiorVolume end
    if (i == 4) then return b2vc_copilotVolume end
    if (i == 4) then return b2vc_copilotVolume end
    if (i == 5) then return b2vc_radioVolume end
    if (i == 6) then return b2vc_enviroVolume end
    if (i == 7) then return b2vc_uiVolume end
    return 0
end

function B2VolumeControl_SetVolume(i,value)
    if (value < 0.0) then value = 0.0 end
    if (value > 1.0) then value = 1.0 end
    if (i == 1) then b2vc_mastervolume = value end
    if (i == 2) then b2vc_exteriorVolume = value end
    if (i == 3) then b2vc_interiorVolume = value end
    if (i == 4) then b2vc_copilotVolume = value end
    if (i == 5) then b2vc_radioVolume = value end
    if (i == 6) then b2vc_enviroVolume = value end
    if (i == 7) then b2vc_uiVolume = value end
end
-- eof