module CloudFormation

using AWS
using AWS: AWSExceptions.AWSException
using EzXML
using MbedTLS: MbedException
using Memento
using Mocking
using OrderedCollections: OrderedDict
using XMLDict

# Improper casing to avoid issues with Module name and AWS.AWSService
@service cloudFormation

const logger = getlogger(@__MODULE__)

# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)

export raw_stack_description, stack_output, stack_description

function describe_stacks(config::AWSConfig, params::AbstractDict)
    return cloudFormation.describe_stacks(params; aws_config=config)
end


const _NRETRIES = 5

# for APIs we don't want to hammer
function cautious_delays(; kwargs...)
    return ExponentialBackOff(; n=_NRETRIES, first_delay=5, max_delay=300, kwargs...)
end

function minimal_delays(; kwargs...)
    return ExponentialBackOff(; n=_NRETRIES, first_delay=0.1, max_delay=60, kwargs...)
end

"""
    raw_stack_description(stack_name::AbstractString) -> String

Returns the description for the specified stack. Can optionally pass in the aws `config`
as a keyword argument.
"""
function raw_stack_description(
    stack_name::AbstractString;
    config::AWSConfig=global_aws_config()
)
    function retry_cond(s, e)
        if e isa AWSException
            if 500 <= e.cause.status <= 504
                debug(logger, "CloudFormation request encountered $(e.code); retrying")
                return (s, true)
            elseif e.cause.status == 429 || (e.cause.status == 400 && e.code == "Throttling")
                debug(logger, "CloudFormation request encountered $(e.code); retrying")
                return (s, true)
            end
        elseif e isa MbedException
            debug(logger, "CloudFormation request encountered $e; retrying")
            return (s, true)
        end

        return (s, false)
    end

    f = retry(delays=cautious_delays(; jitter=0.2), check=retry_cond) do
        @mock describe_stacks(config, Dict("StackName" => stack_name, "return_raw" => true))
    end

    response = String(f())

    return response
end

"""
    stack_output(stack_name::AbstractString) -> OrderedDict

The stack's OutputKey and OutputValue values as a dictionary. Can pass in the aws `config`
as a keyword argument.
"""
function stack_output(stack_name::AbstractString; config::AWSConfig=global_aws_config())
    outputs = OrderedDict{String, String}()
    description = raw_stack_description(stack_name; config=config)

    xml = root(parsexml(description))
    ns = ["ns" => namespace(xml)]
    output_elements = findall("//ns:Outputs/ns:member", xml, ns)

    for el in output_elements
        key = nodecontent(findfirst("ns:OutputKey", el, ns))
        val = nodecontent(findfirst("ns:OutputValue", el, ns))
        outputs[key] = val
    end

    return outputs
end

function output_pair(item::AbstractDict)
    key = item["OutputKey"]::String
    value = if isa(item["OutputValue"], String)
        item["OutputValue"]::String
    elseif isa(item["OutputValue"], AbstractDict) && isempty(item["OutputValue"])
        ""
    else
        throw(ArgumentError("Unhandled output value: $(repr(item["OutputValue"]))"))
    end

    return key => value
end

# BEGIN AWSTools.Cloudformation 0.8.1 deprecations

function stack_description(
    stack_name::AbstractString;
    config::AWSConfig=global_aws_config()
)
    dep_msg = """
        `stack_description(::AbstractString; ::AWSConfig)` is deprecated and will be removed.
        Please use `raw_stack_description(::AbstractString; ::AWSConfig)` instead and handle XML parsing in the calling function.
        We recommend using EzXML.
        """
    Base.depwarn(dep_msg, :stack_description)

    response = xml_dict(raw_stack_description(stack_name))

    return response["DescribeStacksResult"]["Stacks"]["member"]
end

# END AWSTools.Cloudformation 0.8.1 deprecations

end  # CloudFormation
