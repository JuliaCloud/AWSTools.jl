__precompile__()
module S3

using AWS
using AWSS3
using Dates
using FilePathsBase

export S3Path, sync, upload

@deprecate S3Path(args...) AWSS3.S3Path(args...)
@deprecate upload(src::AbstractPath, dest::AWSS3.S3Path) Base.cp(src, dest)

@deprecate(
    presign(path::AWSS3.S3Path, duration::Period=Hour(1); config::AWSConfig=aws_config()),
    AWSS3.s3_sign_url(config, path.bucket, path.key, Dates.value(Second(duration))),
)

# TODO: Remove the sync methods below as they are now pirating.
@deprecate(
    sync(
        src::AbstractString,
        dest::AbstractString;
        delete::Bool=false,
        config::AWSConfig=aws_config(),
    ),
    FilePathsBase.sync(Path(src), Path(dest); delete=delete),
)

end  # S3
