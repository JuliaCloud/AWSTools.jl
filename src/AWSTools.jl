module AWSTools

using AWS
using AWSS3
using Mocking
using Random
using Dates: unix2datetime
export assume_role

@service STS

get_caller_identity() = STS.get_caller_identity()["GetCallerIdentityResult"]
account_id() = (@mock get_caller_identity())["GetCallerIdentityResult"]["Account"]

"""
    assume_role(role_arn, [role_session_name]) -> AWSConfig

Generate a new `AWSConfig` by assuming a new role. In order to use the assumed role you need
to use this config in the various AWS calls you perform.

# Arguments
- `role_arn::AbstractString`: The ARN of the role to assume.
- `role_session_name::AbstractString`: An optional string which is the unique identifier for
    the session name.

# Keywords
- `config::AWSConfig`: The AWS configuration to use when assuming the role.
"""
function assume_role(
    role_arn::AbstractString,
    role_session_name::AbstractString=randstring(16);
    config::AWSConfig=global_aws_config(),
)
    function get_role_creds(role_arn, role_session_name, config)
        response = @mock STS.assume_role(role_arn, role_session_name; aws_config=config)
        response = response["AssumeRoleResult"]
        credentials = response["Credentials"]
        return AWSCredentials(
            credentials["AccessKeyId"],
            credentials["SecretAccessKey"],
            credentials["SessionToken"];
            expiry=unix2datetime(credentials["Expiration"]),
        )
    end

    renew = () -> get_role_creds(role_arn, role_session_name, config)
    creds = renew()
    creds.renew = renew

    return AWSConfig(; creds=creds)
end

include("timeout.jl")
include("CloudFormation.jl")
include("EC2.jl")
include("ECR.jl")
include("Docker.jl")

Base.@deprecate_binding S3 AWSS3

end  # AWSTools
