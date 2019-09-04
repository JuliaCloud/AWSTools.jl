module AWSTools

using AWSCore
using AWSCore.Services: sts
using AWSS3
using Mocking
using Random
using Dates: Period, unix2datetime
export assume_role

get_caller_identity() = sts("GetCallerIdentity")
account_id() = (@mock get_caller_identity())["Account"]

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
    config::AWSConfig=aws_config(),
)
    function get_role_creds(role_arn, role_session_name, config)
        response = @mock sts(
            config,
            "AssumeRole",
            RoleArn=role_arn,
            RoleSessionName=role_session_name,
        )
        credentials = response["Credentials"]
        AWSCredentials(
            credentials["AccessKeyId"],
            credentials["SecretAccessKey"],
            credentials["SessionToken"],
            expiry = unix2datetime(credentials["Expiration"])
        )
    end

    renew = () -> get_role_creds(role_arn, role_session_name, config)
    creds = renew()
    creds.renew = renew

    return aws_config(creds=creds)
end

include("timeout.jl")

include("CloudFormation.jl")
include("EC2.jl")
include("ECR.jl")
include("Docker.jl")
include("S3.jl")

end  # AWSTools
