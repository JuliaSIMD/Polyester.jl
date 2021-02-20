using CheapThreads
using Documenter

DocMeta.setdocmeta!(CheapThreads, :DocTestSetup, :(using CheapThreads); recursive=true)

makedocs(;
    modules=[CheapThreads],
    authors="Chris Elrod <elrodc@gmail.com> and contributors",
    repo="https://github.com/chriselrod/CheapThreads.jl/blob/{commit}{path}#{line}",
    sitename="CheapThreads.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://chriselrod.github.io/CheapThreads.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/chriselrod/CheapThreads.jl",
)
