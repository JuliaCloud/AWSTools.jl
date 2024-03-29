module Docker

using AWS
using ..ECR

export login, pull, push, build

"""
    login(registry_id::Union{AbstractString, Integer}="")

Gets the AWS ECR authorization token and runs the corresponding docker login command.
Takes an optional AWS `config` keyword argument or uses the default.
"""
function login(
    registry_id::Union{AbstractString,Integer}=""; config::AWSConfig=global_aws_config()
)
    return login(ECR.get_login(registry_id; config=config))
end

function login(docker_login::Cmd)
    success(pipeline(docker_login, stdout=stdout, stderr=stderr))
end

"""
    pull(image::AbstractString, tags::AbstractVector{<:AbstractString}=String[])

Pulls a docker image and tags it if `tags` is specified.
"""
function pull(image::AbstractString, tags::AbstractVector{<:AbstractString}=String[])
    run(`docker pull $image`)
    for tag in tags
        run(`docker tag $image $tag`)
    end
end

"""
    push(image::AbstractString)

Pushes a docker image.
"""
function push(image::AbstractString)
    run(`docker push $image`)
end

"""
    build(dir::AbstractString, tag::AbstractString="")

Builds the docker image.
"""
function build(dir::AbstractString, tag::AbstractString="")
    opts = isempty(tag) ? `` : `-t $tag`
    run(`docker build $opts $dir`)
end

end  # Docker
