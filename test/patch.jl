using Base: CmdRedirect

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

