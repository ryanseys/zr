# frozen_string_literal: true

require "fiddle"
require "tmpdir"
require_relative "../../../lib/zr/machine/lower"
require_relative "../../../lib/zr/native/build"
require_relative "../../../lib/zr/obj/jit/fiddle"
require_relative "../../../lib/zr/paths"

module Zr
  module Harness
    # Kernel files, compiled into one unit and loaded into this ruby, so
    # that a test can call their functions through Fiddle and compare the
    # results with CRuby's. `KernelHost` runs the same files as Ruby; a
    # test that uses both checks the compiled code against its source.
    class KernelJIT
      TYPES = { "Word" => Fiddle::TYPE_LONG, "Ptr" => Fiddle::TYPE_VOIDP, "I32" => Fiddle::TYPE_INT, "I8" => Fiddle::TYPE_CHAR,
                "Bool" => Fiddle::TYPE_CHAR, "F64" => Fiddle::TYPE_DOUBLE, "Void" => Fiddle::TYPE_VOID }.freeze

      # The imports of the portable kernel, which any of its files can call.
      IMPORTS = File.join(Paths::RUNTIME, "kernel/imports.rb")

      # `patterns` are globs under lib/zr/runtime/kernel. `constants` sets the
      # constants that the files read from a kernel file outside the unit
      # (the OS layer, for example).
      def initialize(*patterns, constants: {})
        files = patterns.flat_map { |pattern| Dir[File.join(Paths::RUNTIME, "kernel", pattern)].sort }
        raise ArgumentError, "no kernel file matches #{patterns.inspect}" if files.empty?

        Dir.mktmpdir("zr-kernel-jit-") do |dir|
          defined = File.join(dir, "constants.rb")
          File.write(defined, "module Zr::Kern\n#{constants.map { |name, value| "  #{name} = #{value}\n" }.join}end\n")
          lower = Machine.unit([IMPORTS, *files].uniq + [defined])
          unit = Native::Build.unit(lower.functions, lower.data, raw: lower.raw)
          @symbols = Obj::JIT.load(unit, host: Obj::JIT::Fiddle.new)
          @defs = lower.defs
        end
        @functions = {}
      end

      # Calls the kernel function `name` with `args` (Integers, or
      # addresses as Integers), and returns what it returns.
      def call(name, *)
        function = @functions[name] ||= begin
          signature = @defs.fetch(name)
          Fiddle::Function.new(@symbols.fetch(name), signature.params.map { |_, type| TYPES.fetch(type) }, TYPES.fetch(signature.ret))
        end
        function.call(*)
      end
    end
  end
end
