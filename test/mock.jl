const GET_OBJECT_RESP = ""

# TODO: Switch default from `Vector{Any}()` to `[]` when Mocking 0.5.2 is released
get_authorization_token_patch = @patch function get_authorization_token(; registryIds::AbstractVector=Vector{Any}())
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

const DESCRIBE_STACKS_RESP = Dict(
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

