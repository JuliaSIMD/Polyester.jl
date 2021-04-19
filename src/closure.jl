
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
        define_tup!(defined, s::Expr)
    end
end
function define_induction_variables!(defined::Set, ex::Expr) # add `i` in `for i ∈ looprange` to `defined`
    ex.head === :for || return
    loops = ex.args[1]
    if loops.head === :block
        for loop ∈ loops.args
            define!(defined, loop.args[1])
        end
    else
        define!(defined, loops.args[1])
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

static_literals!(s::Symbol) = s
function static_literals!(q::Expr)
    for (i,ex) ∈ enumerate(q.args)
        if ex isa Integer
            q.args[i] = StaticInt(ex)
        elseif ex isa Expr
            static_literals!(ex)
        end
    end
    q
end
function maybestatic!(expr::Expr)::Expr
    if expr.head === :call
        f = first(expr.args)
        if f === :length
            expr.args[1] = static_length
        elseif f === :size && length(expr.args) == 3
            i = expr.args[3]
            if i isa Integer
                expr.args[1] = size
                expr.args[3] = StaticInt(i)
            end
        else
            static_literals!(expr)
        end
    end
    esc(expr)
end
function enclose(exorig::Expr, reserve_per = 0, minbatchsize = 1)
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
    define_induction_variables!(defined, ex)
    if ex.args[1].head === :block
        for i ∈ 2:length(ex.args[1].args)
            extractargs!(arguments, defined, ex.args[1].args[i])
        end
    end
    for i ∈ 2:length(ex.args)
        extractargs!(arguments, defined, ex.args[i])
    end
    firstloop = ex.args[1]
    if firstloop.head === :block
        firstloop = firstloop.args[1]
    end
    loop = firstloop.args[2]
    firstloop.args[2] = Expr(:call, GlobalRef(Base, :(:)), loopstart, loop_step, loop_stop)
    # typexpr_incomplete is missing `funcs`
    q = quote
        $loop_sym = $(maybestatic!(loop))
        $iter_leng = static_length($loop_sym)
        $loop_step = CheapThreads.static_step($loop_sym)
        $loop_offs = CheapThreads.static_first($loop_sym)
    end
    threadtup = Expr(:tuple, iter_leng)
    if minbatchsize ≤ 1
        if reserve_per ≤ 0
            push!(threadtup.args, :(min($iter_leng, CheapThreads.num_threads())))
        else
            push!(threadtup.args, :(min($iter_leng, cld(CheapThreads.num_threads(), $reserve_per))), reserve_per)
        end
    else
        il = :(div($iter_leng, $(StaticInt(minbatchsize))))
        if reserve_per ≤ 0
            push!(threadtup.args, :(min($il, CheapThreads.num_threads())))
        else
            push!(threadtup.args, :(min($il, cld(CheapThreads.num_threads(), $reserve_per))), reserve_per)
        end
    end
    closure = Symbol("##closure##")
    args = Expr(:tuple, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
    closureq = quote
        $closure = let
            @inline ($args, var"##SUBSTART##"::Int, var"##SUBSTOP##"::Int) -> begin
                var"##LOOPSTART##" = var"##SUBSTART##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##"
                var"##LOOP_STOP##" = var"##SUBSTOP##" * var"##LOOP_STEP##" + var"##LOOPOFFSET##" - var"##LOOP_STEP##"
                @inbounds begin
                    $ex
                end
                nothing
            end
        end
    end
    push!(q.args, esc(closureq))
    batchcall = Expr(:call, GlobalRef(CheapThreads, :batch), esc(closure), threadtup, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
    # batchcall = Expr(:call, esc(closure))
    # t = Expr(:tuple, Symbol("##LOOPOFFSET##"), Symbol("##LOOP_STEP##"))
    for a ∈ arguments
        push!(args.args, a)
        # push!(t.args, esc(a))
        push!(batchcall.args, esc(a))
    end
    # push!(batchcall.args, t, 1, iter_leng)
    push!(q.args, batchcall)
    quote
        if CheapThreads.num_threads() == 1
            let
                $(esc(exorig))
            end
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
function interpret_kwarg(arg, reserve_per = 0, minbatch = 1)
    a = arg.args[1]
    v = arg.args[2]
    if a === :reserve
        @assert v ≥ 0
        reserve_per = v
    elseif a === :minbatch
        @assert v ≥ 1
        minbatch = v
    else
        throw(ArgumentError("kwarg $(a) not recognized."))
    end
    reserve_per, minbatch
end
macro batch(arg1, ex)
    reserve, minbatch = interpret_kwarg(arg1)
    enclose(macroexpand(__module__, ex), reserve, minbatch)
end
macro batch(arg1, arg2, ex)
    reserve, minbatch = interpret_kwarg(arg1)
    reserve, minbatch = interpret_kwarg(arg2, reserve, minbatch)
    enclose(macroexpand(__module__, ex), reserve, minbatch)
end

