using AWSSDK.S3: get_object, put_object, delete_object, copy_object
using Base: @deprecate, depwarn
using Compat: split  # Requires Compat v1.0.0

"""
    S3Path <: AbstractPath

Stores information about an s3 object, can be used like an AbstractPath and for
syncing directories.

For example, call `download(src::S3Path)` or `download(src::S3Path, path::AbstractString)`
to download an s3 object to a local file, or `upload(src::AbstractPath, dest::S3Path)` to
upload the local file `src` to the s3 path specified in `dest`.

# Fields
- parts::Tuple: The constituent parts of the s3 path
- bucket::AbstractString: The s3 bucket
- key::AbstractString: The s3 object key
- size::Integer: The size of the s3 object
- last_modified::DateTime: The last modified UTC datetime of the s3 object
"""
struct S3Path <: AbstractPath
    parts::Tuple
    bucket::AbstractString
    key::AbstractString
    size::Int
    last_modified::DateTime  # Expected timezone for this datetime is UTC
end

function S3Path(pieces::Tuple, path::AbstractString, size::Integer, last_modified::DateTime)
    components = split(replace(path, r"^s3://", s""), "/"; limit=2)
    bucket = components[1]
    key = length(components) > 1 ? components[2] : ""
    S3Path(pieces, bucket, key, size, last_modified)
end

"""
    S3Path(pieces::Tuple; size::Integer=0, last_modified::DateTime=DateTime(0)) -> S3Path

Create an S3Path given the constituent pieces of the path, plus optionally specifying
the corresponding s3 object's size and last modified datetime.
"""
function S3Path(pieces::Tuple; size::Integer=0, last_modified::DateTime=DateTime(0))
    path = join(pieces, "/")
    return S3Path(pieces, path, size, last_modified)
end

"""
    S3Path(path::AbstractString) -> S3Path

Create an S3Path given an s3 path of the form: "s3://bucket/key", can optionally specify
the corresponding s3 object's size and last modified datetime.
"""
function S3Path(path::AbstractString; size::Integer=0, last_modified::DateTime=DateTime(0))
    # Don't split on the double `//` of "s3://bucket/key"
    pieces = (split(path, r"(?<!/)/(?!/)")...,)

    # Retain ending `/` info to differentiate s3 folders from objects
    if endswith(path, "/")
        pieces = (pieces..., "")
    end
    return S3Path(pieces, path, size, last_modified)
end

"""
    S3Path(bucket::AbstractString, key::AbstractString) -> S3Path

Create an S3Path given its bucket and key from s3, can optionally specify
the corresponding s3 object's size and last modified datetime.
"""
function S3Path(
    bucket::AbstractString,
    key::AbstractString;
    size::Integer=0,
    last_modified::DateTime=DateTime(0)
)
    key_pieces = split(key, "/")

    # Retain ending `/` info to differentiate s3 folders from objects
    if isempty(key) || endswith(key, "/")
        key_pieces = (key_pieces..., "")
    end
    pieces = ("s3://$bucket", key_pieces...)

    return S3Path(pieces, bucket, key, size, last_modified)
end

function Base.:(==)(a::S3Path, b::S3Path)
    return a.parts == b.parts && a.bucket == b.bucket && a.key == b.key
end

# The following should be implemented in the concrete types
Base.String(object::S3Path) = joinpath(parts(object)...)
FilePaths.parts(object::S3Path) = object.parts
root(path::S3Path) = ""
drive(path::S3Path) = ("s3://", replace(path, r"^s3://", s""))

# S3Path specific methods
Base.show(io::IO, object::S3Path) = print(io, "p\"$(String(object))\"")
Base.real(object::S3Path) = object
Base.size(object::S3Path) = object.size
FilePaths.modified(object::S3Path) = object.last_modified

Base.isdir(object::S3Path) = isempty(object.key) || endswith(object.key, "/")
Base.isfile(object::S3Path) = !isdir(object)

FilePaths.exists(object::S3Path) = length(list_files(object)) > 0 ? true : false

function Base.join(root::S3Path, pieces::Union{AbstractPath, AbstractString}...)
    all_parts = String[]
    root_pieces = parts(root)
    push!(all_parts, root_pieces[1])

    for p in Iterators.flatten((root_pieces[2:end], pieces))
        append!(all_parts, split(p, "/"))
    end

    # Add trailing `/` to folder or bucket
    if length(all_parts) == 1 || endswith(pieces[end], "/")
        push!(all_parts, "")
    end

    return S3Path(Tuple(all_parts))
end

function Base.read(path::S3Path, ::Type{String}; config::AWSConfig=default_aws_config())
    return String(read(path; config=config))
end

function Base.read(path::S3Path; config::AWSConfig=default_aws_config())
    return @mock get_object(config, Dict("Bucket" => path.bucket, "Key" => path.key))
end

function Base.write(
    path::S3Path,
    content::AbstractString,
    mode="w";
    config::AWSConfig=default_aws_config()
)
    @mock put_object(
        config,
        Dict("Body" => content, "Bucket" => path.bucket, "Key" => path.key)
    )
end

function FilePaths.remove(
    object::S3Path;
    recursive::Bool=false,
    config::AWSConfig=default_aws_config()
)
    if isdir(object)
        files = list_files(object)

        if recursive
            map(files) do s3_object
                remove(s3_object; recursive=recursive, config=config)
            end
        elseif length(files) > 0
            error("S3 path $object is not empty. Use `recursive=true` to delete.")
        end
    end

    info(logger, "delete: $object")
    @mock delete_object(config, Dict("Bucket" => object.bucket, "Key" => object.key))
end

function Base.copy(
    src::S3Path,
    dest::S3Path;
    exist_ok::Bool=false,
    overwrite::Bool=false,
    config::AWSConfig=default_aws_config()
)
    if exists(src)
        already_exists = exists(dest)

        if already_exists && !exist_ok
            error("$dest already exists")
        end

        if !already_exists || overwrite
            info(logger, "copy: $src to $dest")
            @mock copy_object(
                config,
                Dict(
                    "Bucket" => dest.bucket,
                    "Key" => dest.key,
                    "headers" => Dict(
                        "x-amz-copy-source" => "/$(src.bucket)/$(src.key)",
                        "x-amz-metadata-directive" => "REPLACE",
                    )
                )
            )
        end
    else
        error("$src is not a valid path")
    end
end

function Base.copy(
    src::S3Path,
    dest::AbstractPath;
    exist_ok=false,
    overwrite=false,
    config::AWSConfig=default_aws_config()
)
    if exists(src)
        already_exists = exists(dest)

        if already_exists && !exist_ok
            error("$dest already exists")
        end

        if !already_exists || overwrite
            info(logger, "download: $src to $dest")
            content = read(src; config=config)
            write(dest, content)
        end
    else
        error("$src is not a valid path")
    end
end

function Base.download(src::S3Path; config::AWSConfig=default_aws_config())
    download(src, joinpath(pwd(), basename(src)); config=config)
end

function Base.download(
    src::S3Path,
    dest::AbstractPath,
    overwrite::Bool=false;
    config::AWSConfig=default_aws_config()
)
    # AWSTools.S3 0.3 deprecation
    if isdir(dest)
        depwarn(
            "`download(r::S3Results, dir::AbstractString)` is deprecated, " *
            "use `download(src::S3Path, Path::AbstractString)` instead.",
            :S3Results
        )
        dest = join(dest, basename(src))
    end

    copy(src, dest; exist_ok=true, overwrite=overwrite, config=config)
    return dest
end

function Base.copy(
    src::AbstractPath,
    dest::S3Path;
    exist_ok=false,
    overwrite=false,
    config::AWSConfig=default_aws_config()
)
    if exists(src)
        already_exists = exists(dest)

        if already_exists && !exist_ok
            error("$dest already exists")
        end

        if !already_exists || overwrite
            info(logger, "upload: $src to $dest")
            content = read(src)
            write(dest, content; config=config)
        end
    else
        error("$src is not a valid path")
    end
end

"""
    upload(src::AbstractPath, dest::S3Path)

Uploads a local file to the s3 path specified by `dest`.
"""
upload

const upload = copy

# BEGIN AWSTools.S3 0.3 deprecations

@deprecate S3Results S3Path

# END AWSTools.S3 0.3 deprecations
