using Documenter, AWSTools, FilePathsBase

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
    repo="https://gitlab.invenia.ca/invenia/AWSTools.jl/blob/{commit}{path}#L{line}",
    sitename="AWSTools.jl",
    authors="Invenia Technical Computing",
    checkdocs = :exports,
    strict = true,
)
