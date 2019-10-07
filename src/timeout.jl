"""
    timeout(f::Function, seconds::Real) -> Union{Some,Nothing}

Executes the provided function `f` and returns the result wrapped in a `Some`. If the given
function takes longer than `seconds` the function is terminated and `nothing` is returned.

Note that the timeout will only work correctly if the called function `f` yields which will
occur automatically if performing an I/O operation.
"""
function timeout(f::Function, seconds::Real)
    result = nothing
    c = Condition()

    try
        # Execute the given function as a task so we can interrupt it if necessary
        t = @async begin
            result = Some(f())
            notify(c)
        end

        # Create a timeout task which aborts the wait early if we hit the timeout.
        # Note: We use an async task here to ensure when `f` finishes before the timeout it
        # is not blocked by the timer.
        @async begin
            # Note: The `pollint` will may cause abort events to occur after the specified
            # timeout. e.g. if `seconds = 1.5` then the abort would occur at 2 seconds.
            timedwait(float(seconds); pollint=1.0) do
                istaskdone(t)
            end
            notify(c)
        end

        wait(c)

        # Kill the function task if it is still executing
        istaskdone(t) || @async Base.throwto(t, InterruptException())
        wait(t)
    catch e
        # Unwrap the TaskFailedException
        if VERSION >= v"1.3.0-alpha.110" && e isa TaskFailedException
            e = e.task.exception
        end

        # Ignore the kill exception
        e isa InterruptException || rethrow(e)
    end

    return result
end
