module CloudFormation

using AWSSDK
using Mocking
using XMLDict
using DataStructures: OrderedDict

using AWSSDK.CloudFormation: describe_stacks

"""
    stack_description(stack_name::AbstractString) -> AbstractDict

Returns the description for the specified stack.
"""
function stack_description(stack_name::AbstractString)
    output = @mock describe_stacks(Dict("StackName" => stack_name))
    return xml_dict(output["DescribeStacksResult"])["Stacks"]["member"]
end

"""
    stack_output(stack_name::AbstractString) -> OrderedDict

The stack's OutputKey and OutputValue values as a dictionary.
"""
function stack_output(stack_name::AbstractString)
    outputs = OrderedDict{String, String}()

    description = stack_description(stack_name)
    for o in description["Outputs"]["member"]
        outputs[o["OutputKey"]] = o["OutputValue"]
    end

    return outputs
end

end  # CloudFormation
