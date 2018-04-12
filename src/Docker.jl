__precompile__()

module Docker

using AWSSDK
using AWSTools.ECR

"""
    login(docker_login_cmd=ECR.get_login())

Gets the AWS ECR authorization token and runs the corresponding docker login command.
"""
function login(docker_login_cmd::Cmd=ECR.get_login())
    success(pipeline(docker_login_cmd, stdout=STDOUT, stderr=STDERR))
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
