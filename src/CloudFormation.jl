__precompile__()

module CloudFormation

using AWSSDK
using Mocking
using XMLDict

import AWSSDK.CloudFormation: describe_stacks

"""
    stack_outputs(stack_name::AbstractString) -> Dict

Returns the description for the specified stack.
"""
function stack_outputs(stack_name::AbstractString)
    output = @mock describe_stacks(Dict("StackName" => stack_name))
    stack = xml_dict(output["DescribeStacksResult"])["Stacks"]["member"]

    # Copy specific keys into a more generic name
    for k in ("ManagerJobQueue", "WorkerJobQueue")
        if haskey(stack, "$(k)Arn")
            stack[k] = stack["$(k)Arn"]
        elseif haskey(stack, "$(k)Name")
            stack[k] = stack["$(k)Name"]
        end
    end

    return stack
end

end  # CloudFormation
