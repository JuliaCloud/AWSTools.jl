const GET_OBJECT_RESP = ""

const GET_AUTH_TOKEN_RESP = Dict(
    "authorizationData" => [
        Dict(
            "authorizationToken" => base64encode("token:password"),
            "proxyEndpoint" => "endpoint"
        ),
    ]
)

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

