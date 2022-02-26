module Term
    # general utils
    include("__text_utils.jl")
    include("_ansi.jl")
    include("_utils.jl")
    
    # don't import other modules
    include("measure.jl")
    include("color.jl")
    include("theme.jl")
    include("highlight.jl")

    # rely on other modules
    include("markup.jl")
    include("style.jl")
    include("segment.jl")

    # renderables, rely heavily on other modules
    include("box.jl")
    include("renderables.jl")
    include("layout.jl")
    include("panel.jl")


    export RenderableText, Panel, TextBox
    export Spacer, vLine, hLine
    export theme, highlight

    # ----------------------------------- base ----------------------------------- #
    import .measure
    using .measure: Measure

    # ----------------------------------- style ---------------------------------- #
    using .markup: extract_markup, MarkupTag, pairup_tags

    using .color: NamedColor, BitColor, RGBColor, get_color

    using .style: MarkupStyle, extract_style

    using .segment: Segment

    """
        Measure(seg::Segment) 

    gives the measure of a segment
    """
    measure.Measure(seg::Segment) = seg.measure

    """
        Measure(segments::Vector{Segment})
    
    gives the measure of a vector of segments
    """
    function measure.Measure(segments::Vector{Segment})
        return Measure(
            max([seg.measure.w for seg in segments]...),
            sum([seg.measure.h for seg in segments])
        )
    end

    # -------------------------------- renderables ------------------------------- #
    using .box

    using .renderables: AbstractRenderable, Renderable, RenderableText

    using .layout: Padding, vstack, hstack, Spacer, vLine, hLine

    using .panel: Panel, TextBox
end

