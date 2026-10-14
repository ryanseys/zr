# The OS layer: each kernel call whose behavior is different on each
# operating system, as a `zr_os_*` function. Each OS defines all of them
# under lib/zr/runtime/kernel/os/<os>/, together with the helpers and
# constants that it needs. The rest of the kernel calls only these
# functions. A call to one that a layer does not define stops the build
# of that target's runtime ("is not a def here").
#
# The OS layer of the core library, under lib/zr/runtime/core/os/<os>/, contains
# the values that ruby gives to the constants of each OS: errno.rb,
# io_constants.rb, process_constants.rb, file_constants.rb and
# clock_constants.rb. Each one runs immediately before the portable file
# that uses it (`Zr::CORE_NAMES`).
#
# The architecture layer, under lib/zr/runtime/kernel/arch/<arch>/, does the
# same for the machine. It gives the `zr_switch` raw function,
# CONTEXT_BYTES, `zr_arch_context_start` and `zr_arch_context_sp`.
module Zr::Kern
end
