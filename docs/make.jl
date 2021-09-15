using Documenter, AWSTools

makedocs(
    modules=[AWSTools],
    format=Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        assets=[
            "assets/invenia.css",
        ],
    ),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/JuliaCloud/AWSTools.jl/blob/{commit}{path}#L{line}",
    sitename="AWSTools.jl",
    authors="Invenia Technical Computing",
    checkdocs = :exports,
    strict = true,
)
