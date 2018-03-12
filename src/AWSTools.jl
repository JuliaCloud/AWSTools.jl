module AWSTools

using Memento

using Mocking

using AWSSDK
using AWSSDK.Batch
using AWSSDK.CloudWatchLogs
using AWSSDK.S3

import AWSSDK.Batch:
    describe_job_definitions, describe_jobs, register_job_definition,
    deregister_job_definition, submit_job

import AWSSDK.S3: get_object
import AWSSDK.CloudWatchLogs: get_log_events

using Compat: Nothing

export
    BatchJob,
    BatchStatus,
    S3Results,
    register,
    deregister,
    submit,
    logs


const logger = getlogger(current_module())
# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)


#####################
#   BatchStatus
#####################
@enum BatchStatus SUBMITTED PENDING RUNNABLE STARTING RUNNING SUCCEEDED FAILED UNKNOWN
const global _status_strs = map(s -> string(s) => s, instances(BatchStatus)) |> Dict
status(x::String) = _status_strs[x]

@doc """
    BatchStatus

An enum for representing different possible batch job states.

See [docs](http://docs.aws.amazon.com/batch/latest/userguide/job_states.html) for details.
""" BatchStatus

#####################################
#       Results
####################################
"""
    AbstractResults

Stores information about how to fetch batch job results.
All subtypes of `AbstractResults` should implement
`Base.download(::AbstractResults, dir)` for downloading results to a file.
"""
abstract type AbstractResults end

"""
    S3Results <: AbstractResults

Stores a bucket and key info for downloading

# Fields
- bucket::String: Stores the bucket where results are stored.
- key::String: The file for all results (the may become prefix in the future).
"""
struct S3Results <: AbstractResults
    bucket::String
    key::String
end

Base.download(r::S3Results) = download(r, pwd())

function Base.download(r::S3Results, dir::String)
    resp = get_object(; Bucket=r.bucket, Key=r.key)
    write(joinpath(dir, r.key), resp["Value"])
end

##################################
#       BatchJob
##################################
"""
    BatchJob

Stores configuration information about a batch job in order to:

- `submit` a new job to batch (and register a revised job definition if necessary)
- `describe` a batch job
- `wait` for a job to complete
- fetch `logs` and `download` job results to a directory

# Fields
- id::String: jobId
- name:String: jobName
- cmd::Cmd: command to execute in the batch job
- image::String: the ECR container image to use for the ECS task
- vcpus::Int: # of cpus available in the ECS task container
- memory::Int: memory allocated to the ECS task container (in MB)
- role::String: IAM role to apply to the ECS task
- definition::String: job definition name or arn
- queue::String: queue to insert the batch job into
- region::String: AWS region to use
- output::Union{AbstractResults, Nothing}: where job results should be stored
"""
mutable struct BatchJob
    id::String
    name::String
    cmd::Cmd
    image::String
    vcpus::Int
    memory::Int
    role::String
    definition::String
    queue::String
    region::String
    output::Union{AbstractResults, Nothing}
end

"""
    BatchJob(; kwargs...)

Handles creating a BatchJob based on various potential defaults.
For example, default job fields can be inferred from an existing job defintion or existing job
(if currently running in a batch job)

Order of priority from lowest to highest:

1. Job definition parameters
2. Inferred environment (e.g., `AWS_BATCH_JOB_ID`` environment variable set)
3. Explict arguments passed in via `kwargs`.
"""
function BatchJob(; kwargs...)
    defaults = Dict(
        :id => "",
        :name => "",
        :cmd => ``,
        :image => "",
        :vcpus => 1,
        :memory => 1024,
        :role => "",
        :definition => "",
        :queue => "",
        :region => "",
        :output => nothing,
    )

    function from_container(container::T) where T <: Associative
        return Dict(
            :cmd => Cmd(Array{String, 1}(container["command"])),
            :image => container["image"],
            :vcpus => container["vcpus"],
            :memory => container["memory"],
            :role => container["jobRoleArn"],
        )
    end

    inputs = Dict(kwargs)

    if haskey(inputs, :definition)
        resp = @mock describe_job_definitions(
            Dict("jobDefinitionName" => inputs[:definition])
        )

        if !isempty(resp["jobDefinitions"])
            details = first(resp["jobDefinitions"])
            d = from_container(details["containerProperties"])
            merge!(defaults, d)
        end
    end

    if haskey(ENV, "AWS_BATCH_JOB_ID")
        # Environmental variables set by the AWS Batch service. They were discovered by
        # inspecting the running AWS Batch job in the ECS task interface.
        job_id = ENV["AWS_BATCH_JOB_ID"]
        job_queue = ENV["AWS_BATCH_JQ_NAME"]

        # Get the zone information from the EC2 instance metadata.
        zone = @mock readstring(pipeline(`curl http://169.254.169.254/latest/meta-data/placement/availability-zone`; stderr=DevNull))
        region = chop(zone)

        # Requires permissions to access to "batch:DescribeJobs"
        resp = @mock describe_jobs(Dict("jobs" => [job_id]))

        if length(resp["jobs"]) > 0
            details = first(resp["jobs"])
            d = from_container(details["container"])
            d[:id] = job_id
            d[:name] = details["jobName"]
            d[:definition] = details["jobDefinition"]
            d[:queue] = job_queue
            d[:region] = region
            merge!(defaults, d)
        else
            warn(logger, "No jobs found with id: $job_id")
        end
    end

    inputs = merge(defaults, inputs)
    return BatchJob(
        inputs[:id],
        inputs[:name],
        inputs[:cmd],
        inputs[:image],
        inputs[:vcpus],
        inputs[:memory],
        inputs[:role],
        inputs[:definition],
        inputs[:queue],
        inputs[:region],
        inputs[:output],
    )
end

"""
    defarn(job::BatchJob) -> String

Looks up the ARN for the latest job definition that can be reused for the current `BatchJob`.
A job definition can only be reused if:

1. status = ACTIVE
2. type = container
3. image = job.image
4. jobRoleArn = job.role
"""
function def_arn(job::BatchJob)
    resp = if isempty(job.definition)
            Dict("jobDefinitions" => [])
        elseif startswith(job.definition, "arn:")
            describe_job_definitions(Dict("jobDefinitions" => [job.definition]))
        else
            describe_job_definitions(Dict("jobDefinitionName" => job.definition))
        end

    isempty(resp["jobDefinitions"]) && return ""
    latest = first(resp["jobDefinitions"])

    for d in resp["jobDefinitions"]
        if d["status"] == "ACTIVE" && d["revision"] > latest["revision"]
            latest = d
        end
    end

    if (
        latest["status"] == "ACTIVE" &&
        latest["type"] == "container" &&
        latest["containerProperties"]["image"] == job.image &&
        latest["containerProperties"]["jobRoleArn"] == job.role
    )
        return latest["jobDefinitionArn"]
    else
        return ""
    end
end

"""
    register(job::BatchJob) -> String

Registers a new job definition. If no job definition exists, a new job definition is created
under the current job specifications, where the new job definition will be `job.name`.
This function returns the new job definition.
"""
function register(job::BatchJob)
    def_name = isempty(job.definition) ? job.name : job.definition
    debug(logger, "Registering job definition $(def_name).")
    input = [
        "type" => "container",
        "containerProperties" => [
            "image" => job.image,
            "vcpus" => job.vcpus,
            "memory" => job.memory,
            "command" => job.cmd.exec,
            "jobRoleArn" => job.role,
        ],
        "jobDefinitionName" => def_name,
    ]

    resp = register_job_definition(input)
    definition = resp["jobDefinitionArn"]
    info(logger, "Registered job definition $definition.")
    return definition
end

"""
    deregister(job::BatchJob) -> Dict

Deregisters an AWS Batch job definition. If the action is successful, this function will
return the empty response dictionary.
"""
function deregister(job::BatchJob)
    def_name = isempty(job.definition) ? job.name : job.definition
    debug(logger, "Deregistering job definition $(def_name).")
    resp = deregister_job_definition(Dict("jobDefinition" => def_name))
    info(logger, "Deregistered job definition $def_name: $resp")
    return resp
end

"""
    submit(job::BatchJob) -> Dict

Handles submitting the batch job and registering a new job definition if necessary.
If no valid job definition exists (see `AWSTools.def_arn`) then a new job definition will be
created. Once the job has been submitted this function will return the response dictionary.
"""
function submit(job::BatchJob)
    definition = def_arn(job)

    if isempty(definition)
        definition = register(job)
    end

    job.definition = definition

    debug(logger, "Submitting job $(job.name).")
    input = [
        "jobName" => job.name,
        "jobQueue" => job.queue,
        "jobDefinition" => job.definition,
        "containerOverrides" => [
            "vcpus" => job.vcpus,
            "memory" => job.memory,
            "command" => job.cmd.exec,
        ]
    ]
    debug(logger, "Input: $input")
    resp = submit_job(input)

    job.id = resp["jobId"]
    info(logger, "Submitted job $(job.name)::$(job.id).")

    return resp
end

"""
    describe(job::BatchJob) -> Dict

If job.id is set then this function is simply responsible for fetch a dictionary for
describing the batch job.
"""
function describe(job::BatchJob)
    isempty(job.id) && throw(logger, ArgumentError("job.id is not set"))
    resp = describe_jobs(; jobs=[job.id])
    isempty(resp["jobs"]) && error(logger, "Job $(job.name)::$(job.id) not found.")
    debug(logger, "Job $(job.name)::$(job.id): $resp")
    return first(resp["jobs"])
end

"""
    wait(
        job::BatchJob,
        cond::Vector{BatchStatus}=[RUNNING, SUCCEEDED],
        failure::Vector{BatchStatus}=[FAILED];
        timeout=600,
        delay=5
    )

Polls the batch job state until it hits one of the conditions in `cond`.
The loop will exit if it hits a `failure` condition and will not catch any excpetions.
The polling interval can be controlled with `delay` and `timeout` provides a maximum
polling time.
"""
function Base.wait(
    job::BatchJob,
    cond::Vector{BatchStatus}=[RUNNING, SUCCEEDED],
    failure::Vector{BatchStatus}=[FAILED];
    timeout=600,
    delay=5
)
    time = 0
    completed = false
    last_state = UNKNOWN

    tic()
    while time < timeout
        j = describe(job)

        time += toq()
        s = status(j["status"])

        if s != last_state
            info(logger, "$(job.name)::$(job.id) status $s")
        end

        last_state = s

        if s in cond
            completed = true
            break
        elseif s in failure
            error(logger, "Job $(job.name)::$(job.id) hit failure condition $s.")
        else
            tic()
            sleep(delay)
        end
    end

    completed || error(logger, "Waiting on job $(job.name)::$(job.id) timed out. Last known state $last_state.")
end

"""
    logs(job::BatchJob) -> Vector{String}

Fetches the logStreamName, fetches the CloudWatch logs and returns a vector of messages.

NOTES:
- The `logStreamName`` isn't available until the job is RUNNING, so you may want to use `wait(job)` or
  `wait(job, [AWSTools.SUCCEEDED])` prior to calling `logs`.
- We do not support pagination, so this function is limited to 10,000 log messages by default.
"""
function logs(job::BatchJob)
    j = describe(job)

    stream = j["container"]["logStreamName"]
    info(logger, "Fetching log events from $stream")

    l = get_log_events(; logGroupName="/aws/batch/job", logStreamName=stream)

    for e in l["events"]
        info(logger, e["message"])
    end

    return l["events"]
end

"""
    download(job::BatchJob, args...)

Handles downloading results for the job.
The methods used for downloading results is dependent on the `AbstractResults` type stored in
the `BatchJob`.
"""
Base.download(job::BatchJob, args...) = download(r.results, args...)

end  # AWSTools
