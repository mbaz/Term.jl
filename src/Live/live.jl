module LiveWidgets
using REPL.TerminalMenus: readkey, terminal
using REPL.Terminals: raw!, AbstractTerminal
using Dates
import Base.Docs: doc as getdocs
using Markdown

import MyterialColors: pink

import Term: default_width, reshape_text
import ..Renderables: AbstractRenderable, RenderableText
import ..Panels: Panel
import ..Measures: Measure
import ..Measures: width as get_width
using ..Consoles
import ..Repr: @with_repr, termshow
import ..Style: apply_style
import ..Layout: Spacer, vLine, vstack, hLine
import ..Compositors: Compositor, render, update!

export AbstractWidget, refresh!, play, key_press, shouldupdate, frame, stop!
export Pager, TabViewer
export SimpleMenu, ButtonsMenu, MultiSelectMenu
export InputBox, TextWidget, Button
export App

include("input.jl")
include("abstract_widget.jl")
include("pager.jl")
include("menu.jl")
include("widgets.jl")
include("tabviewer.jl")
include("app.jl")

end
