using Compat.Dates

using Compat: replace, split, occursin

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
    components = split(replace(path, r"^s3://" => s""), "/"; limit=2, keepempty=false)
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

Create an S3Path given an s3 path of the form: "s3://bucket/key" or "bucket/key".
Can optionally specify the corresponding s3 object's size and last modified datetime.
"""
function S3Path(path::AbstractString; size::Integer=0, last_modified::DateTime=DateTime(0))
    !startswith(path, "s3://") && (path = "s3://$path")

    # Don't split on the double `//` of "s3://bucket/key"
    pieces = split(path, r"(?<!/)/(?!/)"; keepempty=false)

    # Retain ending `/` info to differentiate s3 folders from objects
    endswith(path, "/") && push!(pieces, "")

    return S3Path((pieces...,), path, size, last_modified)
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
    startswith(bucket, "s3://") && (bucket = bucket[6:end])

    key_pieces = split(key, "/"; keepempty=false)

    # Retain ending `/` info to differentiate s3 folders from objects
    if isempty(key) || endswith(key, "/")
        push!(key_pieces, "")
    end
    pieces = ("s3://$bucket", key_pieces...)

    return S3Path(pieces, bucket, key, size, last_modified)
end

FilePathsBase.ispathtype(::Type{S3Path}, str::AbstractString) = startswith(str, "s3://")

function Base.:(==)(a::S3Path, b::S3Path)
    return a.parts == b.parts && a.bucket == b.bucket && a.key == b.key
end

# The following should be implemented in the concrete types
Base.String(object::S3Path) = joinpath(parts(object)...)
FilePathsBase.parts(object::S3Path) = object.parts
root(path::S3Path) = ""

# S3Path specific methods
Base.show(io::IO, object::S3Path) = print(io, "p\"$(String(object))\"")
Base.real(object::S3Path) = object
Base.size(object::S3Path) = object.size
FilePathsBase.modified(object::S3Path) = object.last_modified

Base.isdirpath(path::S3Path) = isempty(path.key) || endswith(path.key, '/')

function Base.isdir(path::S3Path)
    # Note: objects "s3://bucket/a" and "s3://bucket/a/b" can co-exist. If both of these
    # objects exist listing the keys for "s3://bucket/a" returns ["s3://bucket/a"] while
    # "s3://bucket/a/" returns ["s3://bucket/a/b"].
    if isempty(path.key) || path.key == "/"
        key = ""
    elseif endswith(path.key, '/')
        key = path.key
    else
        return false
    end
    objects = @mock _s3_list_objects(default_aws_config(), path.bucket, key; max_items=1)
    length(objects) > 0
end

Base.isfile(path::S3Path) = (isempty(path.key) || endswith(path.key, '/')) ? false : exists(path)
function FilePathsBase.exists(object::S3Path)
    @mock s3_exists(default_aws_config(), object.bucket, object.key)
end

function FilePathsBase.parents(path::S3Path)
    if hasparent(path)
        return map(1:length(parts(path))-1) do i
            S3Path((parts(path)[1:i]..., ""))
        end
    else
        error("$path has no parents")
    end
end

function Base.join(root::S3Path, pieces::Union{AbstractPath, AbstractString}...)
    all_parts = String[]
    root_pieces = parts(root)
    push!(all_parts, root_pieces[1])

    for p in Iterators.flatten((root_pieces[2:end], pieces))
        append!(all_parts, split(p, "/"; keepempty=false))
    end

    # Add trailing `/` to folder or bucket
    if length(all_parts) == 1 || endswith(pieces[end], "/")
        push!(all_parts, "")
    end

    return S3Path(Tuple(all_parts))
end

function Base.readdir(path::S3Path; config::AWSConfig=default_aws_config())
    if isdirpath(path)
        # Only list the files and "dirs" within this S3 "dir"
        all_items = list_files(path; config=config)

        # Only list the basename and not the full key
        return sort!(collect(Set(
            match(r"^([^/]+/?)", sync_key(path, p))[1] for p in all_items
        )))
    else
        throw(ArgumentError("\"$path\" is not a directory"))
    end
end

function Base.read(path::S3Path, ::Type{String}; config::AWSConfig=default_aws_config())
    return String(read(path; config=config))
end

function Base.read(path::S3Path; config::AWSConfig=default_aws_config())
    return @mock s3_get(config, path.bucket, path.key)
end

function Base.write(
    path::S3Path,
    content::Union{String, Vector{UInt8}},
    mode="w";
    config::AWSConfig=default_aws_config()
)
    @mock s3_put(config, path.bucket, path.key, content)
end

function FilePathsBase.remove(
    object::S3Path;
    recursive::Bool=false,
    config::AWSConfig=default_aws_config()
)
    if isdirpath(object)
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
    @mock s3_delete(config, object.bucket, object.key)
end

function Base.copy(
    src::S3Path,
    dest::S3Path;
    exist_ok::Bool=true,
    overwrite::Bool=false,
    config::AWSConfig=default_aws_config()
)
    if exists(src)

        # If `dest` is a directory, copy `src` to that directory with the same name
        if isdirpath(dest)
            dest = join(dest, basename(src))
        end

        already_exists = exists(dest)

        if already_exists && !exist_ok
            error("$dest already exists")
        end

        if !already_exists || overwrite
            info(logger, "copy: $src to $dest")
            @mock s3_copy(
                config,
                src.bucket,
                src.key;
                to_bucket=dest.bucket,
                to_path=dest.key,
            )
        end
    else
        error("$src is not a valid path")
    end
    return dest
end

function Base.copy(
    src::S3Path,
    dest::AbstractPath;
    exist_ok=true,
    overwrite=false,
    config::AWSConfig=default_aws_config()
)
    if exists(src)

        # If `dest` is a directory, download `src` to that directory with the same name
        if isdir(dest)
            dest = join(dest, basename(src))
        end

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
    # Return filename that was downloaded as a String, needed for use with DataDeps
    return dest
end

function Base.copy(
    src::AbstractPath,
    dest::S3Path;
    exist_ok=true,
    overwrite=false,
    config::AWSConfig=default_aws_config()
)
    if exists(src)

        # If `dest` is a directory, upload `src` to that directory with the same name
        if isdirpath(dest)
            dest = join(dest, basename(src))
        end

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
    return dest
end

Base.download(src::S3Path, dest::AbstractPath; kwargs...) = copy(src, dest; kwargs...)
Base.download(src::S3Path, dest::AbstractString; kwargs...) = download(src, Path(dest); kwargs...)
Base.download(src::S3Path; kwargs...) = download(src, Path(pwd()); kwargs...)

"""
    upload(src::AbstractPath, dest::S3Path)

Uploads a local file to the s3 path specified by `dest`.
"""
upload

const upload = Base.copy

# Note: naming copied from Go SDK:
# https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/s3-example-presigned-urls.html
function presign(
    path::S3Path,
    duration::Period=Hour(1);
    config::AWSConfig=default_aws_config(),
)
    AWSS3.s3_sign_url(config, path.bucket, path.key, Dates.value(Second(duration)))
end

# BEGIN AWSTools.S3 0.7 deprecations

function drive(path::S3Path)
    Base.depwarn("`drive(::S3Path)` is deprecated and will be removed in the future.")
    ("s3://", replace(path, r"^s3://" => s""))
end

# END AWSTools.S3 0.7 deprecations
