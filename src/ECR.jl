module ECR

using AWSSDK
using Mocking

using AWSSDK.ECR: get_authorization_token

"""
    get_login(registry_ids::Union{AbstractString, Integer}="") -> Cmd

Gets the AWS ECR authorization token and returns the corresponding docker login command.
"""
get_login

function get_login(registry_id::AbstractString="")
    # Note: Although `get_authorization_token` can take multiple registry IDs at once it
    # will only return a "proxyEndpoint" for the first registry. Additionally, the
    # `aws ecr get-login` command returns a `docker login` command for each registry ID
    # passed in. Because of these factors we'll do our processing on a single registry.

    response = if !isempty(registry_id)
        @mock get_authorization_token(registryIds=[registry_id])
    else
        @mock get_authorization_token()
    end

    authorization_data = first(response["authorizationData"])
    token = String(base64decode(authorization_data["authorizationToken"]))
    username, password = split(token, ':')
    endpoint = authorization_data["proxyEndpoint"]

    return `docker login -u $username -p $password $endpoint`
end

get_login(registry_id::Integer) = get_login(lpad(registry_id, 12, '0'))

# AWSTools 0.1.0 deprecation
@deprecate get_login(ids::AbstractVector) get_login.(ids)

end  # ECR
