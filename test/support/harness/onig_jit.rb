# frozen_string_literal: true

require_relative "kernel_jit"
require_relative "../../../lib/zr/runtime"
require_relative "onig"

module Zr
  module Harness
    # The kernel regexp matcher (lib/zr/runtime/kernel/onig_*.rb), loaded into
    # this ruby with the JIT. It searches with patterns that the core
    # library compiled under this ruby. The tests check its results
    # against ruby's own regexp engine.
    class OnigJIT
      MISMATCH = -1
      TIMEOUT = -23

      def initialize
        Zr::Harness::Onig.load!
        @kernel = KernelJIT.new("onig_*.rb", constants: { "CLOCK_MONOTONIC" => 6 })
      end

      def call(name, *) = @kernel.call(name, *)

      # A compiled pattern (Regexp::Onig::Reg) as the program String the
      # kernel reads.
      def program(compiled) = Regexp::Onig::Program.pack(compiled)

      # Searches `subject` (bytes) with `program`, from byte `start`.
      # Returns nil, [:error, code], or [position, offsets]. The offsets
      # are [beg0, end0, beg1, end1, ...], with -1 for a group that did
      # not match. `backward` searches back to `start`. `at` matches only
      # at `start`, and returns the matched length as the position.
      # `limit` is in nanoseconds, 0 for no limit.
      def search(program, num_mem, subject, start: 0, backward: false, at: false, limit: 0)
        pbuf = Fiddle::Pointer.malloc(program.bytesize, Fiddle::RUBY_FREE)
        pbuf[0, program.bytesize] = program
        sbuf = Fiddle::Pointer.malloc(subject.bytesize + 1, Fiddle::RUBY_FREE)
        sbuf[0, subject.bytesize] = subject.b if subject.bytesize > 0
        n = num_mem + 1
        region = Fiddle::Pointer.malloc(16 * n, Fiddle::RUBY_FREE)
        str = sbuf.to_i
        stop = str + subject.bytesize
        r = if at
              call("zr_onig_match", pbuf.to_i, str, stop, str + start, region.to_i, limit)
            else
              call("zr_onig_search", pbuf.to_i, str, stop, str + start, backward ? str : stop, region.to_i, limit)
            end
        return [:error, r] if r < MISMATCH
        return nil if r == MISMATCH

        [r, region[0, 16 * n].unpack("q<*")]
      end
    end
  end
end
