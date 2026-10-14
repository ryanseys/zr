# frozen_string_literal: true

require_relative "../config"
require_relative "../digests"
require_relative "../paths"
require_relative "store"

module Zr
  module Cache
    # The kernel's lowering (a `Machine::Lower` after `run`), kept between
    # builds. An edit to the core or to the Ruby lowering (`lib/zr/lower`)
    # lowers the core again, but not the kernel: it takes about a second,
    # and a load of the kept one less than that.
    #
    # The key has the target, the path root (a checked kernel's messages
    # name files by it), ZR_KERNEL_CHECKED, each kernel file with its
    # bytes, and the code of each file that the kernel lowering loads
    # (`LOADS`, which `kernel_cache_test.rb` checks).
    module Kernel
      VERSION = 1

      LIB = File.expand_path("..", __dir__) #: String

      # The files that `require "zr/machine/lower"` loads, relative to
      # lib/zr: the kernel lowering, the IR, and zr's Prism, which parses
      # the kernel. Not prism's import.rb: only Ruby::Prism, in a program,
      # loads it. Not the parse cache, which loads at the first parse
      # (`Zr.parse_cache`) and gives the same tree as a parse.
      LOADS = (%w[
        binary.rb bytes.rb config.rb ir.rb ir/analysis.rb ir/effects.rb
        ir/function.rb ir/inst.rb ir/mem2reg.rb ir/promotion.rb library/layout.rb library/ports.rb line_cursor.rb
        machine/description.rb machine/function.rb machine/function/intrinsics.rb machine/lower.rb obj/model.rb
        parse.rb paths.rb prism_shim/prism/prism.rb refused.rb ruby_version.rb session.rb version.rb
      ] + Dir.glob("runtime/ext/prism/**/*.rb", base: LIB) - %w[runtime/ext/prism/ruby/import.rb]).sort.freeze #: Array[String]

      module_function

      # The lowered kernel of `files` (`[[source, path]…]`) for `target`:
      # the kept one, or the block's, which this keeps.
      #: (Target target, Array[[String, String]] files) { () -> Machine::Lower } -> Machine::Lower
      def lowered(target, files)
        key = key(target, files)
        Store.read(:kernel, key) || yield.tap { |unit| Store.write(:kernel, key, unit) }
      end

      #: (Target target, Array[[String, String]] files) -> String
      def key(target, files)
        Store.key(VERSION, target.triple, Paths.root, Config.current.kernel_checked?, loads_digest,
                  *files.flat_map { |source, path| [path, source] })
      end

      #: () -> String
      def loads_digest
        Session.current.memo(:kernel_loads_digest) do
          Digest::SHA256.new.tap do |d|
            LOADS.each { |name| d << name << "\0" << Digests.file(File.join(LIB, name)) << "\0" }
          end.hexdigest
        end
      end
    end
  end
end
