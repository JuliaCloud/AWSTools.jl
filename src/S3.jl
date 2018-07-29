module S3

using AWSSDK
using Memento
using Mocking

using AWSCore
using AWSSDK.S3: get_object

const logger = getlogger(current_module())

# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)


"""
    S3Results

Stores a bucket and key info for downloading. Call `download(r::S3Results)` or
`download(r::S3Results, dir::String)` to actually do the downloading.

# Fields
- bucket::String: Stores the bucket where results are stored.
- key::String: The file for all results (this may become prefix in the future).
"""
struct S3Results
    bucket::String
    key::String
end

function Base.download(r::S3Results; config::AWSConfig=default_aws_config())
    download(r, pwd(); config=config)
end

function Base.download(
    r::S3Results,
    dir::AbstractString;
    config::AWSConfig=default_aws_config()
)
    info(logger, "Downloading s3://$(r.bucket)/$(r.key) to $dir/$(r.key).")
    resp = @mock get_object(config, Bucket=r.bucket, Key=r.key)
    write(joinpath(dir, r.key), resp)
end

end  # S3
