"""
    timeout(f::Function, seconds::Real) -> Union{Some,Nothing}

Executes the provided function `f` and returns the result wrapped in a `Some`. If the given
function takes longer than `seconds` the function is terminated and `nothing` is returned.

Note that the timeout will only work correctly if the called function `f` yields which will
occur automatically if performing an I/O operation.

Note that if `f` throws an exception than the resulting exception will be wrapped inside a
`CompositeException`.
"""
function timeout(f::Function, seconds::Real)
    result = nothing
    c = Condition()

    try
        @sync begin
            # Execute the given function as a task so we can interrupt it if necessary
            t = @async begin
                result = Some(f())
                notify(c)
            end

            # Create a timeout task which aborts the wait early if we hit the timeout
            @async begin
                start = time()
                while !istaskdone(t) && (time() - start) < seconds
                    sleep(1)
                end
                notify(c)
            end

            wait(c)

            # Kill the function task if it is still executing
            istaskdone(t) || Base.throwto(t, InterruptException())
        end
    catch e
        # Ignore the kill exception
        e isa InterruptException || rethrow(e)
    end

    return result
end
