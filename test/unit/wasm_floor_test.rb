# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/backend/wasm"

# A libc call with no wasm form does not stop the build: the module
# carries a function of that name which stops by name when it is called
# (`Native::Build.stops`). That is right for `fork`, for a socket and
# for `Math.acos` -- a wasm program that never asks never pays, and one
# that asks is told what it asked for.
#
# It is wrong for anything every program runs. The allocator and the
# collector run before a program's first line and between each of its
# statements, so a formless call there stops every wasm program there
# is, whatever it does.
#
# This is what that costs when nobody checks. `zr_machine_bytes` read
# `sysconf(_SC_PHYS_PAGES)` to bound the heap's growth, written in the
# belief that wasi's sysconf would answer -1; wasi has no sysconf at
# all, so all 54 of ProgramsTest's wasm rows exited 134 before their
# first line. The whole tier found it. This finds it in a second.
class WasmFloorTest < Minitest::Test
  TARGET = Ze0::Target.fetch("wasm32-wasi")

  # What runs whatever the program is: the heap as it starts, as it
  # hands out a cell, and as it collects.
  ROOTS = %w[zr_heap_init zr_alloc zr_alloc_slow zr_collect zr_collect_kind zr_xmalloc zr_xfree].freeze

  # The calls that are reached on paper and not in a running module,
  # because a branch above them cannot be taken on wasi. A row here is
  # a promise about that branch, so the test fails when one is added
  # and fails again when one stops being needed.
  KNOWN = {
    # `zr_release_fiber` unmaps a fiber's stack, and a fiber on wasi has
    # none: `zr_os_stack_map` (rt/kernel/os/wasi/stack.rb) answers 0 with
    # ENOSYS, so `RFiber.stack(f) != 0` is never true there.
    "munmap" => "zr_release_other"
  }.freeze

  def test_the_heap_calls_nothing_that_has_no_wasm_form
    assert_equal KNOWN.to_a.sort, formless(ROOTS),
                 "a wasm program stops by name before its first line"
  end

  def test_the_roots_are_all_functions_the_kernel_defines
    assert_empty ROOTS - by_name.keys, "a root this test cannot find checks nothing"
  end

  # `[callee, the function that calls it]` for every callee reachable
  # from `roots` that the module would have to stub: not a wasm import,
  # not in the module's floor, and defined nowhere in the kernel.
  def formless(roots)
    found = []
    seen = {}
    queue = roots.dup
    until queue.empty?
      f = by_name[queue.shift]
      next if f.nil? || seen[f.name]

      seen[f.name] = true
      f.callees.each do |c|
        next if c.from || Ze0::Backend::Wasm.floor.include?(c.symbol)

        by_name.key?(c.symbol) ? queue << c.symbol : found << [c.symbol, f.name]
      end
    end
    found.uniq.sort
  end

  # A runtime of this test's own. `Zr.runtime` is the process's, and
  # `Native::Build.lower` lets its IR go as soon as the runtime object
  # is named, so a build anywhere earlier in the process would leave
  # this test no call graph to walk.
  def by_name
    @by_name ||= Ze0::Zr::Runtime.new(TARGET).functions.to_h { |f| [f.name, f] }
  end
end
