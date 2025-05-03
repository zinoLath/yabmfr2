# yabmfr2
A font renderer for LuaSTG with support for multiple styles and fonts on a single line.

## Features
- Load bitmap fonts created using Angelcode's BMFont tool (binary format).
- Render text with multiple styles and fonts on a single line.
- Support for text alignment (horizontal and vertical).
- Apply custom rendering states and effects, such as outlines and transformations.
## Installation
Copy the yabmfr2.lua file into your LuaSTG project directory, and then require it.\
So for example, considering the default LuaSTG file structure:
- package
- - thlib-resources
- - thlib-scripts
- mod
- - your-mod-here.zip

You would insert yabmfr2.lua into either thlib-scripts, or your mod file, and then write:
```lua
local yabmfr2 = require("yabmfr2")
```

If you're using the editor:
1. Include `yabmfr2nodes.lstges` to your "LuaSTG Editor Sharp X Presets" folder located in your "Documents" folder
2. In your project, include said preset
3. Use the "Add File" node in the General tab, and include `yabmfr2.lua` on the root of your project (or if you do put it in a folder, use require's pathing rules to locate it)
4. Lastly, execute the "Load YABMFR2" node.

## Usage
### Loading a Font
To load a bitmap font, use the LoadFont function:
```lua
local yabmfr2 = require("yabmfr2")
local font = yabmfr2.LoadFont("path/to/font.fnt")
```

### Creating a Font Renderer
Create a new font renderer instance with a font list and text:
```lua
local renderer = yabmfr2(font, {"Hello, ", {state = 1}, "world", {state = 0}, "!"})
```

### Rendering Text
Render the text at a specific position with optional rotation and scaling:
```lua
renderer:Render(100, 200, 0, 1, 1)
```

### Setting Text Alignment
Set horizontal and vertical alignment for the text:
```lua
renderer:SetAlignment("center", "top")
renderer:ApplyAlignment()
```

### Applying Custom States
Set custom rendering states, such as blend modes and colors:
```lua
renderer:SetState("mul+alpha", lstg.Color(255, 255, 255, 255))
```

Alternatively, you can limit only certain text states to be changed
```lua
renderer:SetStateSelect(1,"mul+alpha", lstg.Color(255, 255, 0, 0))
```

### Rendering an Outline
Render an outline around the text:
```lua
renderer:RenderOutline(100, 200, 4, 8, 0, 1, 1, lstg.Color(255, 0, 0, 0))
```

### Advanced Customization
Apply a custom function to each render command for further processing:
```lua
renderer:Apply(function(cmd, font, char)
    cmd.x = cmd.x + 10 -- Example: Shift all characters by 10 pixels
end)
```

## License
This project is licensed under the MIT License. See the LICENSE file for details.