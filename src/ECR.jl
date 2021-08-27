module ECR

using AWS
using Base64
using Mocking

# Improper casing to avoid issues with Module name and AWS.AWSService
@service Ecr

function get_authorization_token(config::AWSConfig, params::AbstractDict=Dict{String,Any}())
    dep_msg = """
        `get_authorization_token(config::AWSConfig, params::AbstractDict=Dict{String,Any}())` is deprecated and will be removed.
        Use the AWS @service ECR.get_authorization_token() functionality instead.
        """
    Base.depwarn(dep_msg, :get_authorization_token)
    return Ecr.get_authorization_token(params; aws_config=config)
end

export get_login

"""
    get_login(registry_ids::Union{AbstractString, Integer}="") -> Cmd

Gets the AWS ECR authorization token and returns the corresponding docker login command.
The AWS `config` keyword parameter is optional (will use the default if it's not passed in).
"""
get_login

function get_login(registry_id::AbstractString=""; config::AWSConfig=global_aws_config())
    # Note: Although `get_authorization_token` can take multiple registry IDs at once it
    # will only return a "proxyEndpoint" for the first registry. Additionally, the
    # `aws ecr get-login` command returns a `docker login` command for each registry ID
    # passed in. Because of these factors we'll do our processing on a single registry.

    response = if !isempty(registry_id)
        @mock get_authorization_token(config, Dict("registryIds" => [registry_id]))
    else
        @mock get_authorization_token(config)
    end

    authorization_data = first(response["authorizationData"])
    token = String(base64decode(authorization_data["authorizationToken"]))
    username, password = split(token, ':')
    endpoint = authorization_data["proxyEndpoint"]

    return `docker login -u $username -p $password $endpoint`
end

function get_login(registry_id::Integer; config::AWSConfig=global_aws_config())
    return get_login(lpad(registry_id, 12, '0'); config=config)
end

end  # ECR
