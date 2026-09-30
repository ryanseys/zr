# The leniency of `||=` in the test above does NOT
# apply to `+=`/`&&=` -- confirmed against real `ruby` that those
# still raise on a genuinely undefined constant. An uncaught Ruby
# exception exits the compiled binary nonzero with a message on
# stderr (see `uncaught_raise_with_no_rescue_anywhere_exits_with_the_message`),
# not an abort, so this asserts on the process output directly.

UNDEF += 1

