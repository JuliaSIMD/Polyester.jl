using Polyester
using Documenter

DocMeta.setdocmeta!(Polyester, :DocTestSetup, :(using Polyester); recursive=true)

makedocs(;
    modules=[Polyester],
    authors="Chris Elrod <elrodc@gmail.com> and contributors",
    repo="https://github.com/JuliaSIMD/Polyester.jl/blob/{commit}{path}#{line}",
    sitename="Polyester.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaSIMD.github.io/Polyester.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaSIMD/Polyester.jl",
)
