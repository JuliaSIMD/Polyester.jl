
extractargs!(arguments::Vector{Symbol}, defined::Set, sym) = nothing
function extractargs!(arguments::Vector{Symbol}, defined::Set, sym::Symbol)
    if (sym ∉ defined) && sym ∉ (:nothing, :(+), :(*), :(-), :(/), :(÷), :(<<), :(>>), :(>>>), :zero, :one)
        push!(defined, sym)
        push!(arguments, sym)
    end
    nothing
end
function define_tup!(defined::Set, ex::Expr)
    for a ∈ ex.args
        if a isa Symbol
            push!(defined, a)
        else
            define_tup!(defined, a)
        end
    end
end
function define!(defined::Set, s)
    if s isa Symbol
        push!(defined, s)
    else
        define_tup!(defined, s)
    end
end
function define_induction_variables!(defined::Set, ex::Expr) # add `i` in `for i ∈ looprange` to `defined`
    ex.head === :for || return
    loops = ex.args[1]
    if loops.head === :block
        for loop ∈ loops.args
            push!(defined, loop.args[1])
        end
    else
        push!(defined, loops.args[1])
    end
end

depends_on_defined(defined::Set, f)::Bool = false
depends_on_defined(defined::Set, f::Function)::Bool = f === Threads.threadid
depends_on_defined(defined::Set, f::QuoteNode) = f.value === :threadid
depends_on_defined(defined::Set, f::Symbol)::Bool = (f ∈ defined) || (f === :threadid)
function depends_on_defined(defined::Set, f::Expr)::Bool
    for a ∈ f.args
        depends_on_defined(defined, a) && return true
    end
    false
end
function extractargs!(arguments::Vector{Symbol}, defined::Set, expr::Expr)
    define_induction_variables!(defined, expr)
    head = expr.head
    args = expr.args
    startind = 1
    if head === :call
        startind = 2
    elseif head === :(=)
        arg1 = first(args)
        if arg1 isa Symbol
            push!(defined, arg1)
        elseif Meta.isexpr(arg1, :tuple)
            define_tup!(defined, arg1)
        end
    elseif head ∈ (:inbounds, :loopinfo)#, :(->))
        return
    elseif head === :(.)
        extractargs!(arguments, defined, args[1])
        return
    elseif head === :(->)
        td = copy(defined)
        define!(td, args[1])
        extractargs!(arguments, td, args[1])
        extractargs!(arguments, td, args[2])
        return 
    end
    for i ∈ startind:length(args)
        extractargs!(arguments, defined, args[i])
    end
end

function enclose(exorig::Expr, reserve_per = 0)
    Meta.isexpr(exorig, :for, 2) || throw(ArgumentError("Expression invalid; should be a for loop."))
    ex = copy(exorig)
    loop_sym = Symbol("##LOOP##")
    loopstart = Symbol("##LOOPSTART##")
    loop_step = Symbol("##LOOP_STEP##")
    loop_stop = Symbol("##LOOP_STOP##")
    iter_leng = Symbol("##ITER_LENG##")
    loop_offs = Symbol("##LOOPOFFSET##")

    arguments = Symbol[]#loop_offs, loop_step]
    defined = Set((loop_offs, loop_step));
    extractargs!(arguments, defined, ex)

    firstloop = ex.args[1]
    if firstloop.head === :block
        firstloop = firstloop.args[1]
    end
    loop = firstloop.args[2]
    firstloop.args[2] = Expr(:call, GlobalRef(Base, :(:)), loopstart, loop_step, loop_stop)
    # typexpr_incomplete is missing `funcs`
    q = quote
        $loop_sym = $(esc(loop))
        $iter_leng = static_length($loop_sym)
        $loop_step = CheapThreads.static_step($loop_sym)
        $loop_offs = CheapThreads.static_first($loop_sym)
    end
    threadtup = Expr(:tuple, iter_leng)
    if reserve_per ≤ 0
        push!(threadtup.args, :(min($iter_leng, CheapThreads.num_threads())))
    else
        push!(threadtup.args, :(min($iter_leng, cld(CheapThreads.num_threads(), $reserve_per))), reserve_per)
    end
    closure = Symbol("##closure##")
    args = Expr(:tuple, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
    closureq = quote
        $closure = let
            ($args, var"##SUBSTART##"::Int, var"##SUBSTOP##") -> begin
                var"##LOOPSTART##" = var"##SUBSTART##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - $(Static.One())
                var"##LOOP_STOP##" = var"##SUBSTOP##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - $(Static.One())
                @inbounds begin
                    $ex
                end
                nothing
            end
        end
    end
    push!(q.args, esc(closureq))
    batchcall = Expr(:call, GlobalRef(CheapThreads, :batch), esc(closure), threadtup, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
    for a ∈ arguments
        push!(args.args, a)
        push!(batchcall.args, esc(a))
    end
    push!(q.args, batchcall)
    quote
        if CheapThreads.num_threads() == 1
            $(esc(exorig))
        else
            let
                $q
            end
        end
    end
end

macro batch(ex)
    enclose(macroexpand(__module__, ex))
end
macro batch(reserve_per, ex)
    enclose(macroexpand(__module__, ex), reserve_per)
end

