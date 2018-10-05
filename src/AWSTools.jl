__precompile__()

module AWSTools

using Mocking
using AWSCore.Services: sts

get_caller_identity() = sts("GetCallerIdentity")
account_id() = (@mock get_caller_identity())["Account"]

include("CloudFormation.jl")
include("EC2.jl")
include("ECR.jl")
include("Docker.jl")
include("S3.jl")

end  # AWSTools
