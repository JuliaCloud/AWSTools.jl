__precompile__()
module S3

using AWSCore
using AWSS3
using EzXML
using FilePathsBase
using Memento
using Mocking
using OrderedCollections: OrderedDict
using Retry
using XMLDict

include("S3Path.jl")

export S3Path, upload

const logger = getlogger(@__MODULE__)

# Register the module level logger at runtime so that folks can access the logger via
# `getlogger(MyModule)`. If this line is not included then the precompiled
# `MyModule.logger` won't be registered at runtime.
function __init__()
    Memento.register(logger)
    @warn "S3Path has moved to AWSS3"
end

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
    config::AWSConfig=aws_config(),
)
    sync(Path(src), Path(dest); delete=delete, config=config)
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
    config::AWSConfig=aws_config(),
)
    info(logger, "syncing: $src to $dest")

    # Locally version many codes to insert config as needed
    _isdir(path) = FilePathsBase.isdir(path)
    _isfile(path) = FilePathsBase.isfile(path)
    _mkdir(path; kwargs...) = FilePathsBase.mkdir(path; kwargs...)
    _remove(path) = FilePathsBase.rm(path)


    # Verify the S3 src file or directory exists
    if isa(src, S3Path) && !_isfile(src) && !_isdir(src)
        error(
            "Attemping to sync non-existent S3Path \"$src\". Please verify the file or " *
            "directory exists and that the ending `/` was included if syncing an S3 " *
            "directory."
        )
    end

    # Make sure src and dest directories exist
    if !isa(src, S3Path) && !_isdir(src) && !_isfile(src)
        _mkdir(src; recursive=true)
    end
    if !isa(dest, S3Path) && _isdir(src) && !_isdir(dest) && !_isfile(dest)
        _mkdir(dest; recursive=true, exist_ok=true)
    end

    # Verify src and dest directories are compatible
    if _isfile(src) && _isdir(dest)
        throw(ArgumentError("Cannot sync file $src to a directory ($dest)"))

    elseif _isdir(src) && _isfile(dest)
        throw(ArgumentError("Cannot sync directory $src to a file ($dest)"))

    # Sync two files
    elseif _isfile(src)
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

        @sync for key in to_sync
            curr_src = src_files[key]
            curr_dest = join(dest, sync_key(src, src_files[key]))

            # Copy src file to the destination
            @async sync_path(curr_src, curr_dest; config=config)
        end

        # If delete is true, delete the files that exist in the dest but not the src
        if delete
            to_delete = setdiff(dest_keys, src_keys)

            @sync for key in to_delete
                curr_path = dest_files[key]
                debug(
                    logger,
                    "syncing: (None) -> $curr_path (remove), file does not exist at " *
                    "source ($src/$(sync_key(dest, curr_path))) and delete mode enabled"
                )

                info(logger, "delete: $curr_path")
                @async rm(curr_path)
            end
            # Clean up empty folders on local file system
            cleanup_empty_folders(dest)
        end
    end
end

function sync_path(src::AbstractPath, dest::AbstractPath; kwargs...)
    # Make sure parent directory exists
    mkdir(parent(dest); recursive=true, exist_ok=true)

    # Log `copy` operation for local paths since this isn't logged in FilePathsBase
    info(logger, "copy: $src to $dest")
    cp(src, dest; force=true)
end

sync_path(src::AbstractPath, dest::S3Path) = cp(src, dest; force=true)

sync_path(src::S3Path, dest::S3Path) = cp(src, dest; force=true)

function sync_path(src::S3Path, dest::AbstractPath)
    # Make sure parent directory exists
    mkdir(parent(dest); recursive=true, exist_ok=true)
    cp(src, dest; force=true)
end

"""
    list_files(path::AbstractPath) -> Vector{AbstractPath}

Lists all the files in a local path and subdirectories.
"""
function list_files(path::AbstractPath; kwargs...)
    # We ignore all kwargs, this means we can pass this a config like the S3Path
    # method needs
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
function list_files(path::S3Path)
    all_objects = Vector{AbstractPath}()

    all_items = @mock s3_list_objects(path.config, path.bucket, path.key; delimiter="/")

    for item in all_items
        # Remove the ending `Z` from LastModified field
        haskey(item, "LastModified") || continue

        last_modified_str = if item["LastModified"][end] == 'Z'
            item["LastModified"][1:end - 1]
        else
            item["LastModified"]
        end
        last_modified = DateTime(last_modified_str)

        object = S3Path(string("s3://", path.bucket, "/", item["Key"]))
        !isdir(object) && push!(all_objects, object)
    end

    return all_objects
end

"""
    cleanup_empty_folders(path::AbstractPath)

Recusively deletes empty folders in the path.
Does nothing if called on a `S3Path`.
"""
function cleanup_empty_folders(path::AbstractPath)
    if !isa(path, S3Path) && isdir(path)
        # Delete any empty subfolders
        for name in readdir(path)
            cleanup_empty_folders(join(path, name))
        end
        # Delete folder if it is empty
        if isempty(readdir(path))
            rm(path)
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
    # Note: all operations here are purely based on the filename,
    # so do not need to touch the filesystem, so no AWS config is needed
    # in python's PathLib terminology they are Pure
    if path == src
        return ""
    elseif !isempty(src) && src in parents(path)
        # Remove `src` dir prefix
        return replace(string(path), Regex("^\\Q$(src)\\E/?") => s"")
    else
        return string(path)
    end
end

"""
    should_sync(src::AbstractPath, dest::Union{AbstractPath, Void}) -> Bool

Returns true if the `src` file is newer or of different size than `dest`.
"""
should_sync(src::AbstractPath, dest::Nothing) = true

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
