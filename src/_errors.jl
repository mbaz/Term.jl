import Base.StackTraces: StackFrame
import MyterialColors: pink, indigo_light
import Term: read_file_lines

# ---------------------------------------------------------------------------- #
#                                     MISC                                     #
# ---------------------------------------------------------------------------- #

"""
    function frame_module end 

Get the Module a function is defined in, as a string
"""
function frame_module(frame::StackFrame)::Union{Nothing,String}
    m = Base.parentmodule(frame)

    if m !== nothing
        while parentmodule(m) !== m
            pm = parentmodule(m)
            pm == Main && break
            m = pm
        end
    end
    m = !isnothing(m) ? string(m) : frame_module(string(frame.file))

    return m
end

"""
Get module from file path.
"""
frame_module(path::String) = startswith(path, "./") ? "Base" : nothing

"""
Get module for a pointer obj
"""
frame_module(pointer::Ptr) = frame_module(StackTraces.lookup(pointer)[1])
frame_module(iip::Base.InterpreterIP) = string(iip.mod)

"""
    should_skip

A frame should skip if it's in Base or an installed package.
"""
should_skip(frame::StackFrame) =
    frame_module(frame) ∈ ["Base", "Main", nothing] || (
        contains(string(frame.file), r"[/\\].julia[/\\]") ||
        contains(string(frame.file), r"julia[/\\]stdlib") ||
        contains(string(frame.file), r"julia[/\\]lib") ||
        contains(string(frame.file), r"julialang.language")
    )
should_skip(frame::StackFrame, hide::Bool) = hide ? should_skip(frame) : false
should_skip(pointer::Ptr) = should_skip(StackTraces.lookup(pointer)[1])
should_skip(pointer::Ptr, hide::Bool) = hide ? should_skip(pointer) : false
should_skip(iip::Base.InterpreterIP) = true
should_skip(iip::Base.InterpreterIP, hide::Bool) = true

"""
    parse_kw_func_name(frame::StackFrame)

Kw function calls have a weird name, parse arguments to get 
a proper function signature.
"""
function parse_kw_func_name(frame::StackFrame)::String
    linfo = frame.linfo
    def = linfo.def

    if isa(def, Method)
        sig = linfo.specTypes
        argnames = Base.method_argnames(def)
        ftypes = map(i -> fieldtype(sig, i), 1:length(argnames)) |> collect

        kwargs = map(
            i -> fieldname(ftypes[2], i) => fieldtype(ftypes[2], 1),
            1:length(fieldnames(ftypes[2])),
        )

        # get function name and name/type of args and kwargs
        func = replace(string(def.name), "##kw" => "") * "("
        func *= join(
            map(i -> string(argnames[i]) * "::" * string(ftypes[i]), 4:length(ftypes)),
            ", ",
        )
        !isempty(kwargs) && begin
            func *= "; " * join(["$k::$v" for (k, v) in kwargs], ", ")
        end
        func *= ")"
    else
        func = string(sprint(StackTraces.show_spec_linfo, frame))
    end
    return func
end

"""
    get_frame_function_name

Get and stylize a function's name/signature
"""
function get_frame_function_name(frame::StackFrame, ctx::StacktraceContext)
    # get the name of the error function
    func = sprint(StackTraces.show_spec_linfo, frame)
    (contains(func, "##kw") || contains(func, "kwerr")) &&
        (func = parse_kw_func_name(frame))

    # format function name
    func =
        replace(
            func,
            r"(?<group>^[^(]+)" => SubstitutionString(
                "{$(ctx.theme.func)}" * s"\g<0>" * "{/$(ctx.theme.func)}",
            ),
        ) |>
        highlight |>
        apply_style

    # reshape but taking care of potential curly bracktes
    func =
        reshape_text(escape_brackets(func), ctx.func_name_w; ignore_markup = true) |>
        unescape_brackets
    func = do_by_line(remove_markup, func)
    return RenderableText(func)
end

# ---------------------------------------------------------------------------- #
#                              render source code                              #
# ---------------------------------------------------------------------------- #

"""
    render_error_code_line(frame::StackFrame; δ=2)

Create a `Panel` showing formatted Julia code for a frame's error line. 
The parameter `δ` speciies how many lines above/below the error line to show. 
"""
function render_error_code_line(ctx::StacktraceContext, frame::StackFrame; δ = 2)
    # get code as string
    error_source = nothing
    try
        error_source = load_code_and_highlight(string(frame.file), Int(frame.line); δ = δ)
    catch
        error_source = nothing
    end
    (isnothing(error_source) || length(error_source) == 0) && return nothing

    code_error_panel = Panel(
        str_trunc(error_source, ctx.code_w - 4; ignore_markup = false);
        fit = δ == 0,
        style = δ > 0 ? "$(ctx.theme.text_accent) dim" : "dim",
        width = ctx.code_w,
        subtitle_justify = :center,
        subtitle = δ > 0 ? "error line" : nothing,
        subtitle_style = "default $(ctx.theme.text_accent)",
        height = δ > 0 ? nothing : 1,
        padding = (0, 1, 0, 0),
    )
    return "  " * RenderableText("│\n╰─"; style = "dim") * code_error_panel
end

"""
    function add_stack_frame! end

Create a Term visualization of info and metadata about a 
stacktrace frame.
"""
function add_stack_frame! end

"""
    add_stack_frame!(frame::StackFrame, ctx::StacktraceContext, num::Int;  kwargs...)

Renders a panel with:
 - frame number
 - function name/signature
 - source code at error line
"""
function add_stack_frame!(
    content,
    frame::StackFrame,
    ctx::StacktraceContext,
    as_panel::Bool,
    num::Int;
    δ = 3,
    kwargs...,
)
    # get the name of the error function
    func = get_frame_function_name(frame, ctx)

    # get other information about the function 
    inline =
        frame.inlined ? RenderableText("inlined"; style = "bold dim $(ctx.theme.text)") : ""
    c = frame.from_c ? RenderableText("from C"; style = "bold dim $(ctx.theme.text)") : ""

    # make function line
    func_line = (frame.inlined || frame.from_c) ? func / hstack(inline, c; pad = 1) : func

    # make file line & load source code around error and render it
    panel_content = if length(string(frame.file)) > 0
        file = Base.fixup_stdlib_path(string(frame.file))
        Base.stacktrace_expand_basepaths() &&
            (file = something(Base.find_source_file(file), file))
        Base.stacktrace_contract_userdir() && (file = Base.contractuser(file))
        file_line = RenderableText(
            "{dim}$(file):{bold $(ctx.theme.text_accent)}$(frame.line){/bold $(ctx.theme.text_accent)}{/dim}";
            width = ctx.func_name_w,
        )

        _out = func_line / file_line
        error_source = render_error_code_line(ctx, frame; δ = δ)
        isnothing(error_source) || (_out /= error_source)
        _out
    else
        func_line
    end

    # make panel and add it to content
    panel = if as_panel
        Panel(
            panel_content;
            title_style = "$(ctx.theme.err_btframe_panel) bold",
            padding = (2, 2, 0, 0),
            fit = false,
            width = ctx.frame_panel_w,
            kwargs...,
        )
    else
        pad("   " * func_line; width = ctx.frame_panel_w, method = :right)
    end

    numren = vertical_pad("{dim}($num){/dim} ", height(panel), :center)
    push!(content, numren * panel)
end

add_stack_frame!(content, pointer::Ptr{Nothing}, args...; δ = 3, kwargs...) =
    add_stack_frame!(content, StackTraces.lookup(pointer)[1], args...; δ = δ, kwargs...)

add_stack_frame!(content, pointer::Base.InterpreterIP, args...; δ = 3, kwargs...) =
    RenderableText("pointer")

"""
    add_new_module_name!(content, ctx::StacktraceContext, curr_modul)

When a frame belonging to a module different from the previous one is shown, 
print the new module's name.
"""
function add_new_module_name!(content, ctx::StacktraceContext, curr_module)
    push!(
        content,
        hLine(
            ctx.module_line_w,
            "{default $(ctx.theme.text_accent)}In module {$(ctx.theme.err_accent) bold}$(curr_module){/$(ctx.theme.err_accent) bold}{/default $(ctx.theme.text_accent)}";
            style = "$(ctx.theme.err_accent) dim",
        ),
    )
end

"""
    add_number_frames_skipped!(content, ctx, to_skip, num, bt, n_skipped, skipped_frames_modules)

Add some text explaining how many frames were skipped from the stacktrace visualization
and to which modules they belonged. 
"""
function add_number_frames_skipped!(
    content,
    ctx::StacktraceContext,
    to_skip,
    num,
    bt,
    n_skipped,
    skipped_frames_modules,
)
    if (to_skip == false || num == length(bt) - 1) && n_skipped > 0
        color = ctx.theme.err_btframe_panel
        accent = ctx.theme.err_accent

        # get the name of the modules
        modules = join(unique(string.(filter(!isnothing, skipped_frames_modules))), ", ")
        modules = filter(x -> x != "nothing", modules)
        in_mod = length(modules) == 0 ? "" : "in {$accent}$modules{/$accent}"
        word = plural("frame", length(modules))

        # render
        push!(
            content,
            cvstack(
                hLine(ctx.module_line_w; style = "$color dim"),
                RenderableText(
                    "Skipped {bold}$n_skipped{/bold} $word $in_mod";
                    width = ctx.frame_panel_w,
                    justify = :center,
                    style = color,
                ),
                hLine(ctx.module_line_w; style = "$color dim");
                pad = 0,
            ),
        )
    end
end

"""
    render_backtrace(bt::Vector; reverse_backtrace = true, max_n_frames = 30)

Main error backtrace rendering function. 
It renders each frame in a stacktrace after some filtering (e.g. to hide frames in BASE).
It takes care of hiding frames when there's a large number of them. 
"""
function render_backtrace(
    ctx::StacktraceContext,
    bt::Vector;
    reverse_backtrace = true,
    max_n_frames = 30,
    hide_frames = true,
)
    length(bt) == 0 && return RenderableText("")
    if reverse_backtrace
        bt = reverse(bt)
    end

    # get the module each frame's code line is defined in
    frames_modules = frame_module.(bt)
    # println.(zip(frames_modules, should_skip.(bt)))

    """
    Define a few variables to keep track of during stack 
    trace rendering. These are used when some frames are hidden
    to keep track of how many and in which module they were, 
    and to know when to print a message to indicate that
    the stack trace entered a new module.
    """

    added_skipped_message = false
    N = length(bt)
    prev_frame_module = nothing # keep track of the previous' frame module
    n_skipped = 0  # keep track of number of frames skipped (e.g in Base)
    skipped_frames_modules = []
    tot_frames_added = 0

    # render each frame
    content = AbstractRenderable[]
    for (num, frame) in enumerate(bt)
        # if the current frame's module differs from the previous one, show module name
        curr_module = frames_modules[num]
        (
            curr_module != prev_frame_module &&
            !should_skip(frame, hide_frames) &&
            !isnothing(curr_module)
        ) && add_new_module_name!(content, ctx, curr_module)

        # render frame
        frame_panel_kwargs = if num == 1  # first frame is highlighted
            Dict(
                :subtitle => reverse_backtrace ? "TOP LEVEL" : "ERROR LINE",
                :subtitle_style =>
                    reverse_backtrace ? "$(ctx.theme.text_accent)" :
                    "bold $(ctx.theme.text_accent)",
                :subtitle_justify => :right,
                :style => ctx.theme.err_btframe_panel,
            )
        elseif num == length(bt)  # last frame is highlighted
            Dict(
                :subtitle => reverse_backtrace ? "ERROR LINE" : "TOP LEVEL",
                :subtitle_style =>
                    reverse_backtrace ? "bold $(ctx.theme.text_accent)" :
                    "$(ctx.theme.text_accent)",
                :subtitle_justify => :right,
                :style => ctx.theme.err_btframe_panel,
            )

        else  # inside frames are printed without an additional panel around
            Dict(:style => "hidden")
        end
        δ = num in (1, length(bt)) ? 2 : 0
        (should_skip(frame, hide_frames) && num ∉ [1, length(bt)]) || add_stack_frame!(
            content,
            frame,
            ctx,
            num ∈ [1, length(bt)],
            num;
            δ = δ,
            frame_panel_kwargs...,
        )

        # keep track of frames being skipped
        if num != 1 || num != length(bt)
            # skip extra panels for long stack traces
            if tot_frames_added > max_n_frames &&
               num < length(bt) - 5 &&
               added_skipped_message == false
                skipped_line = hLine(
                    ctx.module_line_w,
                    "{bold dim}$(N - max_n_frames - 2){/bold dim}{$(ctx.theme.err_btframe_panel) dim} frames skipped{/$(ctx.theme.err_btframe_panel) dim}";
                    style = "$(ctx.theme.err_btframe_panel) dim",
                )
                push!(content, skipped_line)
                added_skipped_message = true
            else  # show "inner" frames without additional info, hide base optionally
                # skip frames in modules like Base
                to_skip = should_skip(frame, hide_frames)

                # show number of frames skipped
                if (to_skip == false || num == length(bt) - 1) && n_skipped > 0
                    add_number_frames_skipped!(
                        content,
                        ctx,
                        to_skip,
                        num,
                        bt,
                        n_skipped,
                        skipped_frames_modules,
                    )
                end

                # skip
                to_skip && begin
                    n_skipped += 1
                    push!(skipped_frames_modules, curr_module)
                    continue
                end

                # show
                n_skipped, skipped_frames_modules = 0, []
                tot_frames_added += 1
            end
        else
            tot_frames_added += 1
        end

        isnothing(curr_module) || (prev_frame_module = curr_module)
    end

    # create an overall panel
    return Panel(
        cvstack(content..., pad = 1);
        padding = (2, 2, 1, 1),
        subtitle = "Error Stack",
        style = "$(ctx.theme.er_bt) dim",
        subtitle_style = "bold $(ctx.theme.er_bt) default",
        title = "Error Stack",
        title_style = "bold $(ctx.theme.er_bt) default",
        fit = false,
        justifty = :left,
        width = ctx.out_w,
    )
end
