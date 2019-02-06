using Documenter, AWSTools, FilePathsBase

makedocs(
    modules=[AWSTools],
    format=Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://gitlab.invenia.ca/invenia/AWSTools.jl/blob/{commit}{path}#L{line}",
    sitename="AWSTools.jl",
    authors="Nicole Epp, Curtis Vogt, Rory Finnegan, etc.",
    assets=[
        "assets/invenia.css",
    ],
    checkdocs = :exports,
    strict = true,
)
