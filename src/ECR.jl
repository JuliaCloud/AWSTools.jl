__precompile__()

module ECR

using AWSSDK
using Mocking

import AWSSDK.ECR: get_authorization_token

"""
    get_login(registry_ids::AbstractVector=String[]) -> Cmd

Gets the AWS ECR authorization token and returns the corresponding docker login command.
"""
get_login

function get_login(registry_ids::AbstractVector{<:AbstractString}=String[])
    resp = if !isempty(registry_ids)
        @mock get_authorization_token(registryIds=registry_ids)
    else
        @mock get_authorization_token()
    end

    authorization_data = first(resp["authorizationData"])
    token = String(base64decode(authorization_data["authorizationToken"]))
    username, password = split(token, ':')
    endpoint = authorization_data["proxyEndpoint"]

    return `docker login -u $username -p $password $endpoint`
end

get_login(registry_ids::AbstractVector{<:Integer}) = get_login(lpad.(registry_ids, 12, '0'))

end  # ECR
