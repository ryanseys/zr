# frozen_string_literal: true

require "fiddle"
require "tmpdir"
require_relative "../../../lib/zr/machine/lower"
require_relative "../../../lib/zr/native/build"
require_relative "../../../lib/zr/obj/jit/fiddle"
require_relative "kernel_files"

module Zr
  module Harness
    # Kernel files, compiled into one unit and loaded into this ruby, so
    # that a test can call their functions through Fiddle and compare the
    # results with CRuby's. `KernelHost` runs the same files as Ruby; a
    # test that uses both checks the compiled code against its source.
    class KernelJIT
      TYPES = { "Word" => Fiddle::TYPE_LONG, "Ptr" => Fiddle::TYPE_VOIDP, "I32" => Fiddle::TYPE_INT, "I8" => Fiddle::TYPE_CHAR,
                "Bool" => Fiddle::TYPE_CHAR, "F64" => Fiddle::TYPE_DOUBLE, "Void" => Fiddle::TYPE_VOID }.freeze

      # `patterns` name the files (KernelFiles). `constants` sets the
      # constants that the files read from a kernel file outside the unit
      # (the OS layer, for example).
      def initialize(*patterns, constants: {})
        files = KernelFiles[*patterns]
        Dir.mktmpdir("zr-kernel-jit-") do |dir|
          defined = File.join(dir, "constants.rb")
          File.write(defined, "module Zr::Kern\n#{constants.map { |name, value| "  #{name} = #{value}\n" }.join}end\n")
          lower = Machine.unit(files + [defined])
          unit = Native::Build.unit(lower.functions, lower.data, raw: lower.raw)
          @symbols = Obj::JIT.load(unit, syscalls: Obj::JIT::Fiddle.new)
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
