using Base: CmdRedirect

get_caller_identity = @patch function get_caller_identity()
    account_id = join(rand(0:9, 12), "")
    Dict(
        "Account" => account_id,
        "Arn" => "arn:aws:iam::$account_id:user/UserName",
        "UserId" => join(rand('A':'Z', 21), ""),
    )
end

instance_availability_zone_patch = @patch function readstring(cmd::CmdRedirect)
    url = cmd.cmd.exec[2]
    @assert endswith(url, "availability-zone")
    return "us-east-1a"
end

get_authorization_token_patch = @patch function get_authorization_token(; registryIds::AbstractVector=[])
    id = lpad(isempty(registryIds) ? "" : first(registryIds), 12, '0')
    Dict(
        "authorizationData" => [
            Dict(
                "authorizationToken" => base64encode("AWS:password"),
                "proxyEndpoint" => "https://$(id).dkr.ecr.us-east-1.amazonaws.com"
            ),
        ]
    )
end

describe_stacks_patch = @patch function describe_stacks(args...)
    Dict(
        "DescribeStacksResult" =>
        """
        <Stacks>
          <member>
            <StackId>Stack Id</StackId>
            <StackName>Stack Name</StackName>
            <Description>Stack Description</Description>
          </member>
        </Stacks>"""
    )
end

