using Documenter, AWSTools

makedocs(
    modules=[AWSTools],
    format=:html,
    pages=[
        "Home" => "index.md",
    ],
    repo="https://gitlab.invenia.ca/invenia/AWSTools.jl/blob/{commit}{path}#L{line}",
    sitename="AWSTools.jl",
    authors="rofinn",
    assets=[
        "assets/invenia.css",
     ],
)
