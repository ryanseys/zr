# frozen_string_literal: true
# zr-test: runtime
# zr-test: on wasm

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/backend/wasm"

# A libc call with no wasm form does not stop the build. The module
# contains a function of that name that stops, with a message that
# gives the name, when it is called (`Native::Build.stops`). That is
# correct for `fork`, a socket, or `Math.acos`: only a program that
# makes the call gets the stop.
#
# It is not correct for code that every program runs. The allocator and
# the collector run before the first line and between statements, so a
# call with no wasm form there stops every wasm program. For example, a
# `sysconf(_SC_PHYS_PAGES)` call in `zr_machine_bytes` made all 54 wasm
# tests of ProgramsTest exit 134 before their first line, because wasi
# has no sysconf. Only the full tier found that. This test finds it in
# a second.
class WasmLibcShimsTest < Minitest::Test
  TARGET = Zr::Target.fetch("wasm32-wasi")

  # The code that runs for every program: the heap when it starts, when it
  # gives out a cell, and when it collects.
  ROOTS = %w[zr_heap_init zr_alloc zr_alloc_slow zr_collect zr_collect_kind zr_xmalloc zr_xfree].freeze

  # Calls that the call graph reaches but a running module does not,
  # because a branch before them cannot be taken on wasi. Each entry is a
  # claim about that branch, so the test fails when an entry is added and
  # fails again when an entry is no longer necessary.
  KNOWN = {}.freeze #: Hash[String, String]

  # The functions that a program module gives the runtime: its toplevels.
  PROGRAM = %w[zr_prelude zr_toplevel zr_gem_prelude].freeze

  # The roots must be functions of the kernel, or the walk checks
  # nothing.
  def test_the_heap_calls_nothing_that_has_no_wasm_form
    assert_empty ROOTS - by_name.keys, "a root this test cannot find checks nothing"
    assert_equal KNOWN.to_a.sort, formless(ROOTS),
                 "a wasm program stops by name before its first line"
  end

  # Each libc call of the kernel has a wasi form (kernel/os/wasi), so no
  # call stops the module with "has no wasm form": a call that WASI cannot
  # make fails with an errno that the program can rescue (missing.rb).
  def test_each_libc_call_has_a_wasi_form
    assert_equal [], formless(by_name.keys).map(&:first).uniq - PROGRAM
  end

  # `[callee, the function that calls it]` for each callee reachable from
  # `roots` that the module must stub: not a wasm import, not in the
  # module's floor, and not defined in the kernel.
  def formless(roots)
    found = []
    seen = {}
    queue = roots.dup
    until queue.empty?
      f = by_name[queue.shift]
      next if f.nil? || seen[f.name]

      seen[f.name] = true
      f.callees.each do |c|
        next if c.from || Zr::Backend::Wasm.libc_shims.include?(c.symbol)

        by_name.key?(c.symbol) ? queue << c.symbol : found << [c.symbol, f.name]
      end
    end
    found.uniq.sort
  end

  # The kernel of a runtime that only this test uses: the heap and the
  # collector are kernel code, and the kernel comes from its cache, where
  # the whole runtime lowered the core too (30 s). `Zr::Runtime.for`
  # belongs to the process, and `Native::Build.lower` releases its IR as
  # soon as it gets the runtime object, so an earlier build in the
  # process would leave this test no call graph to walk.
  def by_name
    @by_name ||= Zr::Runtime.new(TARGET).unit.functions.to_h { |f| [f.name, f] }
  end
end
