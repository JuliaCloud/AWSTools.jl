__precompile__()
module S3

using AWSCore
using FilePaths
using Memento
using Mocking
using XMLDict

using AWSSDK.S3: list_objects_v2
using Compat: @__MODULE__

export S3Path, sync, upload

const logger = getlogger(@__MODULE__)
# Register the module level logger at runtime so that folks can access the logger via
# `getlogger(MyModule)`. If this line is not included then the precompiled
# `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)

include("S3Path.jl")

"""
    sync(src::AbstractString, dest::AbstractString; delete::Bool=false)

Syncs local directories and S3 prefixes. Recursively copies new and updated files from the
source path to the destination. Only creates folders in the destination if they contain
one or more files.

Source and destination can be local file paths or s3 paths (formatted as "s3://bucket/key"
and including the ending `/` that differentiates S3 folders from objects).

If the delete flag is set then files that exist in the destination but not the source will
be deleted.
"""
function sync(
    src::AbstractString,
    dest::AbstractString;
    delete::Bool=false,
    config::AWSConfig=default_aws_config(),
)
    src = AbstractPath(src)
    dest = AbstractPath(dest)
    sync(src, dest; delete=delete)
end

"""
    sync(src::AbstractPath, dest::AbstractPath; delete::Bool=false)

Syncs directories and S3 prefixes. Recursively copies new and updated files from the source
path to the destination. Only creates folders in the destination if they contain one
or more files.

If the delete flag is set then files that exist in the destination but not the source will
be deleted.
"""
function sync(
    src::AbstractPath,
    dest::AbstractPath;
    delete::Bool=false,
    config::AWSConfig=default_aws_config(),
)
    info(logger, "syncing: $src to $dest")

    # Make sure src and dest directories exist
    if !isa(src, S3Path) && !isdir(src) && !isfile(src)
        mkdir(src; recursive=true)
    end
    if !isa(dest, S3Path) && isdir(src) && !isdir(dest) && !isfile(dest)
        mkdir(dest; recursive=true, exist_ok=true)
    end

    # Verify src and dest directories are compatible
    if isfile(src) && isdir(dest)
        throw(ArgumentError("Cannot sync file $src to a directory ($dest)"))

    elseif isdir(src) && isfile(dest)
        throw(ArgumentError("Cannot sync directory $src to a file ($dest)"))

    # Sync two files
    elseif isfile(src)
        # Copy src file to the destination
        sync_path(src, dest; config=config)

    # Sync two directories
    else
        src_files = Dict()
        dest_files = Dict()

        # Map files in src and dest with their sync keys
        for file in list_files(src; config=config)
            src_files[sync_key(src, file)] = file
        end
        for file in list_files(dest; config=config)
            dest_files[sync_key(dest, file)] = file
        end

        src_keys = Set(keys(src_files))
        dest_keys = Set(keys(dest_files))

        # Copy new or modified files to their corresponding destination paths
        to_sync = filter(src_keys) do x
            should_sync(
                src_files[x],
                get(dest_files, x, nothing)
            )
        end

        for key in to_sync
            curr_src = src_files[key]
            curr_dest = join(dest, sync_key(src, src_files[key]))

            # Copy src file to the destination
            sync_path(curr_src, curr_dest; config=config)
        end

        # If delete is true, delete the files that exist in the dest but not the src
        if delete
            to_delete = setdiff(dest_keys, src_keys)

            for key in to_delete
                curr_path = dest_files[key]
                debug(
                    logger,
                    "syncing: (None) -> $curr_path (remove), file does not exist at " *
                    "source ($src/$(sync_key(dest, curr_path))) and delete mode enabled"
                )

                if isa(curr_path, S3Path)
                    remove(curr_path; config=config)
                else
                    info(logger, "delete: $curr_path")
                    remove(curr_path)
                end
            end
            # Clean up empty folders on local file system
            cleanup_empty_folders(dest)
        end
    end
end

function sync_path(src::AbstractPath, dest::AbstractPath; kwargs...)
    # Make sure parent directory exists
    mkdir(parent(dest); recursive=true, exist_ok=true)

    # Log `copy` operation for local paths since this isn't logged in FilePaths
    info(logger, "copy: $src to $dest")
    copy(src, dest; overwrite=true, exist_ok=true)
end

function sync_path(src::AbstractPath, dest::S3Path; config::AWSConfig=default_aws_config())
    copy(src, dest; overwrite=true, exist_ok=true, config=config)
end

function sync_path(src::S3Path, dest::S3Path; config::AWSConfig=default_aws_config())
    copy(src, dest; overwrite=true, exist_ok=true, config=config)
end

function sync_path(src::S3Path, dest::AbstractPath; config::AWSConfig=default_aws_config())
    # Make sure parent directory exists
    mkdir(parent(dest); recursive=true, exist_ok=true)
    copy(src, dest; overwrite=true, exist_ok=true, config=config)
end


"""
    list_files(path::AbstractPath) -> Vector{AbstractPath}

Lists all the files in a local path and subdirectories.
"""
function list_files(path::AbstractPath; kwargs...)
    all_files = Vector{AbstractPath}()

    if isfile(path)
        push!(all_files, path)

    elseif isdir(path)
        listdir_names = readdir(path)

        for name in listdir_names
            append!(all_files, list_files(join(path, name)))
        end
    end
    return all_files
end

"""
    list_files(path::S3Path) -> Vector{AbstractPath}

List all the objects in an s3 bucket that include the specified s3 path's key as a prefix
in their key.
"""
function list_files(path::S3Path; config::AWSConfig=default_aws_config())
    all_objects = Vector{AbstractPath}()

    results = xml_dict(
        @mock list_objects_v2(config, Dict("Bucket" => path.bucket, "prefix" => path.key))
    )

    if "ListAllMyBucketsResult" in keys(results)
        throw(ArgumentError("No s3 bucket found with the name: \"$(path.bucket)\""))
    end

    results = results["ListBucketResult"]

    if "Contents" in keys(results)
        all_items = if parse(Int, results["KeyCount"]) > 1
            results["Contents"]
        else
            [results["Contents"]]
        end

        for item in all_items
            # Remove the ending `Z` from LastModified field
            last_modified_str = if item["LastModified"][end] == 'Z'
                item["LastModified"][1:end - 1]
            else
                item["LastModified"]
            end
            last_modified = DateTime(last_modified_str)

            object = S3Path(
                path.bucket,
                item["Key"];
                size=parse(item["Size"]),
                last_modified=last_modified,
            )
            !isdir(object) && push!(all_objects, object)
        end
    end
    return all_objects
end

"""
    AbstractPath(path::AbstractString) -> AbstractPath

Identifies whether the path is from the local filesystem or if it is an s3 path (denoted by
it starting with "s3://").
"""
AbstractPath(path::AbstractString) = startswith(path, "s3://") ? S3Path(path) : Path(path)

"""
    cleanup_empty_folders(path::AbstractPath)

Recusively deletes empty folders in the path.
"""
function cleanup_empty_folders(path::AbstractPath)
    if !isa(path, S3Path) && isdir(path)
        # Delete any empty subfolders
        for name in readdir(path)
            cleanup_empty_folders(join(path, name))
        end
        # Delete folder if it is empty
        if isempty(readdir(path))
            remove(path)
        end
    end
end

"""
    sync_key(src::AbstractPath, path::AbstractPath) -> String

Returns the key of the path without including the base syncing directory.

For example if we did `sync("dir1", "dir2")`, a file located at "dir1/folder/myfile" would
have a sync_key of "folder/myfile" and would be synced to "dir2/folder/myfile".
"""
function sync_key(src::AbstractPath, path::AbstractPath)
    prefix = endswith(src, "/") ? src : "$src/"

    if path == prefix
        return ""
    elseif !isempty(prefix) && startswith(path, prefix)
        # Get the indices of the directory prefix that are not part of the
        # comparison sync key
        prefix_indices = search(path, prefix)[end]
        return path[prefix_indices+1:end]  # Remove src directory prefix
    else
        return path
    end
end

"""
    should_sync(src::AbstractPath, dest::Union{AbstractPath, Void}) -> Bool

Returns true if the `src` file is newer or of different size than `dest`.
"""
should_sync
should_sync(src::AbstractPath, dest::Void) = true

function should_sync(src::AbstractPath, dest::AbstractPath)
    same_size = size(src) == size(dest)
    newer_src_file = modified(src) > modified(dest)
    if !same_size || newer_src_file
        debug(
            logger,
            "syncing: $src -> $dest, " *
            "size: $(size(src)) -> $(size(dest)), " *
            "modified time: $(modified(src)) -> $(modified(dest))"
        )
        return true
    else
        return false
    end
end

end  # S3
