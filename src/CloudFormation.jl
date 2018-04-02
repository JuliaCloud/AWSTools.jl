__precompile__()

module CloudFormation

using AWSSDK
using Mocking
using XMLDict

import AWSSDK.CloudFormation: describe_stacks

"""
    stack_description(stack_name::AbstractString) -> Dict

Returns the description for the specified stack.
"""
function stack_description(stack_name::AbstractString)
    output = @mock describe_stacks(Dict("StackName" => stack_name))
    return xml_dict(output["DescribeStacksResult"])["Stacks"]["member"]
end

end  # CloudFormation
