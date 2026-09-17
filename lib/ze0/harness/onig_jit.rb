# frozen_string_literal: true

require "fiddle"
require "tmpdir"
require_relative "../machine/lower"
require_relative "../native/build"
require_relative "../obj/jit/fiddle"
require_relative "../paths"
require_relative "../zr"

module Ze0
  module Harness
    # The kernel matcher (rt/kernel/onig_*.rb) JIT-loaded into this ruby,
    # searching programs the core compiled under this ruby: what the
    # checks and tools/regexp_diff.rb hold to ruby's own engine.
    class OnigJIT
      TYPES = { "Word" => Fiddle::TYPE_LONG, "Ptr" => Fiddle::TYPE_VOIDP, "I32" => Fiddle::TYPE_INT, "I8" => Fiddle::TYPE_CHAR,
                "Bool" => Fiddle::TYPE_CHAR, "Void" => Fiddle::TYPE_VOID }.freeze
      MISMATCH = -1
      TIMEOUT = -23

      def initialize
        Zr.require_onig
        Dir.mktmpdir("ze0-onig-") do |dir|
          consts = File.join(dir, "consts.rb")
          File.write(consts, "CLOCK_MONOTONIC = 6\n")
          lower = Machine.unit(Dir[File.join(Paths::RT, "kernel/onig_*.rb")].sort + [consts])
          unit = Native::Build.unit(lower.functions, lower.data, raw: lower.raw)
          @symbols = Obj::JIT.load(unit, host: Obj::JIT::Fiddle.new)
          @defs = lower.instance_variable_get(:@defs)
        end
        @fns = {}
      end

      def call(name, *args)
        fn = @fns[name] ||= begin
          d = @defs.fetch(name)
          Fiddle::Function.new(@symbols.fetch(name), d.params.map { |_, t| TYPES.fetch(t) }, TYPES.fetch(d.ret))
        end
        fn.call(*args)
      end

      # A compiled pattern (Regexp::Onig::Reg) as the program String the
      # kernel reads.
      def program(compiled) = Regexp::Onig::Program.pack(compiled)

      # The search of `program` over `subject` (bytes) from byte `start`:
      # nil, [:error, code], or [position, offsets] with the offsets as
      # [beg0, end0, beg1, end1, ...] and -1 for a group that did not
      # take part. `backward` searches back to `start`; `at` matches at
      # `start` alone and answers the length matched as the position.
      # `limit` is nanoseconds, 0 for none.
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
