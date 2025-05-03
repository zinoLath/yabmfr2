--[[
MIT License

Copyright (c) 2025 João Henrique Flauzino

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Description:
This project is a font renderer for LuaSTG, designed to support multiple styles
and fonts on a single line. It provides functionality for loading bitmap fonts,
managing text alignment, rendering text with transformations, and applying
custom effects such as outlines and state-based styling.
]]

--#region Class Definition
local class = {}
setmetatable(class,class)
function class:__call()
    local new = {}
    setmetatable(new,{
        __call = function(self,...)
            return class.New(self,...)
        end
    })
    return new
end
function class:New(...)
    local obj = {}
    obj.__index = self
    self.__create(obj,...)
    setmetatable(obj, obj)
    return obj
end
--#endregion
---@class yabmfr2
---@field fontlist table<string,table> Font list containing loaded fonts.
---@field text table<string> Text to be rendered.
---@field commands table<bmfrendercommand> Render commands for each character in the text.
---@field alignment string Text alignment (e.g., "left", "center", "right").
---@field valign string Vertical alignment (e.g., "top", "center", "bottom").
---@field maxWidth number Maximum width of the rendered text.
---@field widths table<number> Widths of each line in the text.
---@field LoadFont fun(path:string):yabmfr2font Loads a bitmap font from the specified file path.
---@field Create fun(self:yabmfr2,fontlist:table,text:string|table) Creates a new font renderer instance with the specified font list and text.
---@field Generate fun(self:yabmfr2) Generates the render commands for the text based on the loaded font.
---@field SetAlignment fun(self:yabmfr2,alignment:string,valign:string) Sets the text alignment and vertical alignment for rendering.
---@field ApplyAlignment fun(self:yabmfr2,sx:number,sy:number) Applies the specified alignment to the rendered text.
---@field Render fun(self:yabmfr2,x:number,y:number,rot:number,sx:number,sy:number) Renders the text at the specified position with the given rotation and scale.
---@field SetState fun(self:yabmfr2,blend:string,c1:lstg.Color,c2?:lstg.Color,c3?:lstg.Color,c4?:lstg.Color) Sets the rendering state for the text with the specified blend mode and colors.
---@field SetStateSelect fun(self:yabmfr2,state:number,blend:string,c1:lstg.Color,c2?:lstg.Color,c3?:lstg.Color,c4?:lstg.Color) Sets the rendering state for the text with the specified blend mode and colors for a specific state.
---@field RenderOutline fun(self:yabmfr2,x:number,y:number,rad:number,count:number,rot:number,sx:number,sy:number,color:Color) Renders an outline around the text with the specified parameters.
---@field Apply fun(self:yabmfr2,func:function) Applies a custom function to each render command for further processing.
local yabmfr2 = class()
local buffer = require("string.buffer")
local ffi = require "ffi"
ffi.cdef[[
typedef struct {
    uint32_t fontid;
    uint32_t charid;
    double x;
    double y;
    double _x; //_x and _y are to store the clean positions. clean sx/sy is 1 and clean rot is 0
    double _y;
    double rot;
    double sx;
    double sy;
    uint32_t id;
    uint32_t lineid;
    uint32_t state;
    uint32_t extra;
    double extraf;
} bmfrendercommand;
]]

--#region File Loading Helpers
local function bytes2uint(str)
    local uint = 0
    for i = 1, #str do
        uint = uint + str:byte(i) * 0x100^(i-1)
    end
    return uint
end
local function bytes2int(str)
    local uint = bytes2uint(str)
    local max = 0x100 ^ #str
    if uint >= max / 2 then
        return uint - max
    end
    return uint
end
local function readInt(buf, size)
    return bytes2int(buf:get(size))
end
local function readUInt(buf, size)
    return bytes2uint(buf:get(size))
end
local function readStr(buf)
    local str = ""
    while true do
        local c = buf:get(1)
        if c == "\0" then
            break
        end
        str = str .. c
    end
    return str
end
local function readBlock1(buf,size)
    local self = {}
    self.size = readInt(buf, 2)
    self.bitfield = readInt(buf, 1)
    self.charset = readInt(buf, 1)
    self.stretchH = readInt(buf, 2)
    self.aa = readInt(buf, 1)
    self.paddingUp = readInt(buf, 1)
    self.paddingRight = readInt(buf, 1)
    self.paddingDown = readInt(buf, 1)
    self.paddingLeft = readInt(buf, 1)
    self.spacingHoriz = readInt(buf, 1)
    self.spacingVert = readInt(buf, 1)
    self.outline = readInt(buf, 1)
    self.name = readStr(buf)
    return self
end
local function readBlock2(buf,size)
    local self = {}
    self.lineHeight = readUInt(buf,2)
    self.base = readUInt(buf,2)
    self.scaleW = readUInt(buf,2)
    self.scaleH = readUInt(buf,2)
    self.pages = readUInt(buf,2)
    self.bitfield = readUInt(buf,1)
    self.alphaChnl = readUInt(buf,1)
    self.redChnl = readUInt(buf,1)
    self.greenChnl = readUInt(buf,1)
    self.blueChnl = readUInt(buf,1)
    return self
end
local function readBlock3(buf,size)
    local self = {}
    while size > 0 do
        local str = readStr(buf)
        table.insert(self, str)
        size = size - #str - 1
    end
    return self
end
local function readBlock4(buf,size)
    local self = {}
    local charcount = size/20
    for i = 1, charcount, 1 do
        local id = readUInt(buf,4)
        local c = {}
        self[id] = c
        c.id = id
        c.x = readUInt(buf,2)
        c.y = readUInt(buf,2)
        c.width = readUInt(buf,2)
        c.height = readUInt(buf,2)
        c.xoffset = readInt(buf,2)
        c.yoffset = readInt(buf,2)
        c.xadvance = readInt(buf,2)
        c.page = readInt(buf,1)
        c.chnl = readInt(buf,1)
    end
    return self
end
local function readBlock5(buf,size)
    local self = {}
    local kerncount = size/10
    for i = 1, kerncount, 1 do
        local first = readUInt(buf,4)
        local second = readUInt(buf,4)
        local amount = readInt(buf,2)
        self[first] = self[first] or {}
        self[first][second] = amount
    end
    return self
end
local getPath = function(str,sep)sep=sep or'/'return str:match("(.*"..sep..")")end
--#endregion
---Loads a bitmap font from the specified file path. The font is created using Angelcode's BMFont tool, exported as a binary.
---@param path string
---@return table
function yabmfr2.LoadFont(path)
    local self = {}
    local str = lstg.LoadTextFile(path)
    local buf = buffer.new(string.len(str))
    buf:set(str)
    buf:skip(4)
    
    while #buf > 0 do
        local blocktype = readUInt(buf, 1)
        local block1size = readUInt(buf, 4)
        if blocktype == 1 then
            self.info = readBlock1(buf, block1size)
        end
        if blocktype == 2 then
            self.common = readBlock2(buf, block1size)
        end
        if blocktype == 3 then
            self.pages = readBlock3(buf, block1size)
        end
        if blocktype == 4 then
            self.chars = readBlock4(buf, block1size)
        end
        if blocktype == 5 then
            self.kerning = readBlock5(buf, block1size)
        end
    end
    self.textures = {}
    for k,v in pairs(self.pages) do
        self.textures[k] = "font:"..v
        lstg.LoadTexture(self.textures[k],getPath(path)..v,true)
    end
    for k,v in pairs(self.chars) do
        --print(k,PrintTable(v))
        lstg.LoadImage(self.textures[v.page+1]..k,self.textures[v.page+1],v.x,v.y,v.width,v.height)
    end
    return self
end

---Constructor function for the yabmfr2 class.
---@param fontlist table A table containing font data loaded using yabmfr2.LoadFont.
---@param text string|table A table containing the text to be rendered. If a string is provided, it will be converted to a table.
function yabmfr2:__create(fontlist, text)
    self.fontlist = fontlist
    if type(text) == "string" then
        text = {text}
    end
    self.text = text
    
    self.commands = {}

    self.widths = {}
    self.maxWidth = 0

    self.colors = {lstg.Color(255,255,255,255),lstg.Color(255,255,255,255),lstg.Color(255,255,255,255),lstg.Color(255,255,255,255)}
    yabmfr2.Generate(self)
end

---Function to generate the rendering commands for the text.
function yabmfr2:Generate()
    local data = {
        state = 0,
        font = 1,
        xcursor = 0,
        linecount = 0,
        prevchar = -1,
    }
    for id, str in ipairs(self.text) do
        if type(str) == "table" then
            data.state = str.state or data.state
            data.font = str.font or data.font
            data.linecount = str.linecount or data.linecount
            data.xcursor = str.xcursor or data.xcursor
        else
            local i = 1
            while i <= #str do
                local cstr = str:sub(i, i)
                ---if cstr:byte() > 128 then
                ---    cstr = str:sub(i, i+4)
                ---    i = i + 3
                ---end
                local c
                if cstr:byte() < 128 then
                    c = cstr:byte()
                elseif cstr:byte() < 224 then
                    cstr = str:sub(i, i+2)
                    i = i + 1
                    local b1, b2 = cstr:byte(1, 2)
                    c = (b1 - 192) * 64 + (b2 - 128)
                elseif cstr:byte() < 240 then
                    cstr = str:sub(i, i+3)
                    i = i + 2
                    local b1, b2, b3 = cstr:byte(1, 3)
                    c = (b1 - 224) * 4096 + (b2 - 128) * 64 + (b3 - 128)
                elseif cstr:byte() < 248 then
                    cstr = str:sub(i, i+4)
                    i = i + 3
                    local b1, b2, b3, b4 = cstr:byte(1, 4)
                    c = (b1 - 240) * 262144 + (b2 - 128) * 4096 + (b3 - 128) * 64 + (b4 - 128)
                end
                --print(c,cstr)
                if c == ("\n"):byte() then
                    data.xcursor = 0
                    data.linecount = data.linecount + 1
                    local cmd = ffi.new("bmfrendercommand")
                    cmd.fontid = data.font
                    cmd.charid = c
                    table.insert(self.commands, cmd)
                else
                    local char = self.fontlist[data.font].chars[c]
                    local font = data.font
                    while not char and self.fontlist[font+1] do
                        font = font + 1
                        char = self.fontlist[font].chars[c]
                    end
                    if char then
                        local cmd = ffi.new("bmfrendercommand")
                        --print(font, c, char)
                        cmd.fontid = font
                        cmd.charid = c
                        cmd.x = data.xcursor + char.xoffset + char.width/2
                        if data.prevchar ~= ("\n"):byte() then
                            local kerning = 0
                            if self.fontlist[font].kerning then
                                if self.fontlist[font].kerning[c] then
                                    if self.fontlist[font].kerning[c][data.prevchar] then
                                        kerning = self.fontlist[font].kerning[c][data.prevchar]
                                    end
                                end
                            end
                            cmd.x = cmd.x + kerning
                        end
                        cmd.y = data.linecount * -self.fontlist[data.font].common.lineHeight - char.yoffset - char.height/2
                        cmd._x = cmd.x
                        cmd._y = cmd.y
                        cmd.rot = 0
                        cmd.sx = 1
                        cmd.sy = 1
                        cmd.id = id
                        cmd.state = data.state
                        cmd.extra = 0
                        cmd.extraf = 0
                        cmd.lineid = data.linecount
                        table.insert(self.commands, cmd)
                        data.xcursor = data.xcursor + char.xadvance
                    end
                end
                i = i + 1
            end
        end
    end
    local lineWidths = {}
    local currentWidth = 0
    local lineIndex = 1
    self.maxWidth = 0

    for _, cmd in ipairs(self.commands) do
        if cmd.charid == ("\n"):byte() then
            lineWidths[lineIndex] = currentWidth
            self.maxWidth = math.max(self.maxWidth, currentWidth)
            currentWidth = 0
            lineIndex = lineIndex + 1
        else
            local char = self.fontlist[cmd.fontid].chars[cmd.charid]
            currentWidth = currentWidth + char.xadvance
        end
    end

    lineWidths[lineIndex] = currentWidth
    self.maxWidth = math.max(self.maxWidth, currentWidth)
    self.widths = lineWidths
    --print(self.text[1],self.maxWidth)
end

---Sets the text alignment and vertical alignment for rendering.
---@param alignment string The horizontal alignment of the text (e.g., "left", "center", "right").
---@param valign string The vertical alignment of the text (e.g., "top", "center", "bottom").
function yabmfr2:SetAlignment(alignment, valign)
    self.alignment = alignment
    self.valign = valign
end

---Applies the specified alignment to the rendered text.
function yabmfr2:ApplyAlignment()
    if not self.alignment then return end
    local maxWidth = 0
    local lineWidths = {}
    local currentWidth = 0
    local lineIndex = 1

    for _, cmd in ipairs(self.commands) do
        if cmd.charid == ("\n"):byte() then
            lineWidths[lineIndex] = currentWidth
            maxWidth = math.max(maxWidth, currentWidth)
            currentWidth = 0
            lineIndex = lineIndex + 1
        else
            local char = self.fontlist[cmd.fontid].chars[cmd.charid]
            currentWidth = currentWidth + char.xadvance
            --print(currentWidth)
        end
    end
    lineWidths[lineIndex] = currentWidth
    maxWidth = math.max(maxWidth, currentWidth)

    local xOffset = 0
    lineIndex = 1
    for i, cmd in ipairs(self.commands) do
        if cmd.charid == ("\n"):byte() then
            xOffset = 0
            lineIndex = lineIndex + 1
        else
            if self.alignment == "center" then
                xOffset = lineWidths[lineIndex]/2
            elseif self.alignment == "right" then
                xOffset = lineWidths[lineIndex]
            else
                xOffset = 0
            end
            cmd.x = cmd._x - xOffset
        end
    end
    local yOffset = 0
    for i, cmd in ipairs(self.commands) do
        if cmd.charid == ("\n"):byte() then
        else
            if self.valign == "center" then
                yOffset = #lineWidths * self.fontlist[1].common.lineHeight/2
            elseif self.valign == "bottom" then
                yOffset = #lineWidths * self.fontlist[1].common.lineHeight
            else
                yOffset = 0
            end
            cmd.y = cmd._y + yOffset
        end
    end
end

---Renders the text at the specified position with the given rotation and scale.
---@param x number The x-coordinate of the rendering position.
---@param y number The y-coordinate of the rendering position.
---@param rot number The rotation angle in degrees.
---@param sx number The horizontal scale factor.
---@param sy number The vertical scale factor.
function yabmfr2:Render(x,y,rot,sx,sy)
    rot = rot or 0
    sx = sx or 1
    sy = sy or sx
    local coss, sins = cos(rot), sin(rot)
    local mcoss, msins = cos(-rot), sin(-rot)
    for i = 1, #self.commands do
        local cmd = self.commands[i]
        local font = self.fontlist[cmd.fontid]
        local char = font.chars[cmd.charid]
        if cmd.charid ~= ("\n"):byte() then
            local _x = x + cmd.x * mcoss*sx + cmd.y * msins*sy
            local _y = y + cmd.y * mcoss*sy - cmd.x * msins*sx
            local _rot = cmd.rot+rot
            local _sx = cmd.sx*sx
            local _sy = cmd.sy*sy
            local id = cmd.id
            local state = cmd.state
            local extra = cmd.extra
            local extraf = cmd.extraf
            local tex = self.fontlist[cmd.fontid].textures[char.page+1]..cmd.charid
            lstg.Render(tex, _x, _y, _rot, _sx, _sy)
        end
    end
end

---Sets the rendering state for the text with the specified blend mode and colors.
---@param blend string The blend mode to be used (e.g., "","mul+add", "mul+alpha", "add+alpha").
---@param c1 lstg.Color The top-left color to be used for rendering. If the following colors are not provided, c1 will be used for all corners.
---@param c2? lstg.Color The top-right color to be used for rendering (optional).
---@param c3? lstg.Color The bottom-right color to be used for rendering (optional).
---@param c4? lstg.Color The bottom-left color to be used for rendering (optional).
function yabmfr2:SetState(blend, c1,c2,c3,c4)
    self.colors = {c1,c2 or c1,c3 or c1,c4 or c1}
    for i = 1, #self.commands do
        --do break end
        local cmd = self.commands[i]
        local font = self.fontlist[cmd.fontid]
        local char = font.chars[cmd.charid]
        if cmd.charid ~= ("\n"):byte() then
            local tex = self.fontlist[cmd.fontid].textures[char.page+1]..cmd.charid
            lstg.SetImageState(tex, blend, c1,c2 or c1,c3 or c1,c4 or c1)
        end
    end
end

---Sets the rendering state for the text with the specified blend mode and colors for a specific state.
---@param state number The state of the text to be rendered.
---@param blend string The blend mode to be used (e.g., "","mul+add", "mul+alpha", "add+alpha").
---@param c1 lstg.Color The top-left color to be used for rendering. If the following colors are not provided, c1 will be used for all corners.
---@param c2? lstg.Color The top-right color to be used for rendering (optional).
---@param c3? lstg.Color The bottom-right color to be used for rendering (optional).
---@param c4? lstg.Color The bottom-left color to be used for rendering (optional).
function yabmfr2:SetStateSelect(state,blend, c1,c2,c3,c4)
    for i = 1, #self.commands do
        --do break end
        local cmd = self.commands[i]
        local font = self.fontlist[cmd.fontid]
        local char = font.chars[cmd.charid]
        if cmd.charid ~= ("\n"):byte() and cmd.state == state then
            local tex = self.fontlist[cmd.fontid].textures[char.page+1]..cmd.charid
            lstg.SetImageState(tex, blend, c1,c2 or c1,c3 or c1,c4 or c1)
        end
    end
end

---Renders an outline around the text with the specified parameters.
---@param x number The x-coordinate of the outline position.
---@param y number The y-coordinate of the outline position.
---@param rad number The radius of the outline.
---@param count number The number of outline segments.
---@param rot number The rotation angle of the outline.
---@param sx number The horizontal scale factor of the outline.
---@param sy number The vertical scale factor of the outline.
---@param color lstg.Color The color of the outline.
function yabmfr2:RenderOutline(x,y,rad,count,rot,sx,sy,color)
    rad = rad or 4
    count = count or 8
    color = color or Color(255,0,0,0)
    local prev_color = self.colors
    for i=1, count do
        local ang = i*360/count
        local xoff, yoff =  rad*math.cos(math.rad(ang)), rad*math.sin(math.rad(ang))
        self:SetState("",color)
        self:Render(x+xoff,y+yoff,rot,sx,sy)
    end
    self:SetState("",prev_color[1],prev_color[2],prev_color[3],prev_color[4])
end

---Applies a custom function to each render command for further processing.
---@param func fun(cmd:bmfrendercommand, font:table, char:table) function The function to be applied to each render command.
function yabmfr2:Apply(func)
    for i = 1, #self.commands do
        local cmd = self.commands[i]
        local font = self.fontlist[cmd.fontid]
        local char = font.chars[cmd.charid]
        if cmd.charid ~= ("\n"):byte() then
            func(cmd,font,char)
        end
    end
end

return yabmfr2