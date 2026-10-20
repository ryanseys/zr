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
    # (`loads`, which `kernel_cache_test.rb` checks).
    module Kernel
      VERSION = 1

      LIB = File.expand_path("..", __dir__) #: String

      # The files that start the kernel lowering, relative to lib/zr: the
      # lowering, and zr's Prism, which parses the kernel (parse.rb finds it
      # by `require "prism"`). The key covers each file that they load
      # (`Digests.required`). Not the parse cache, which loads at the first
      # parse (`Zr.parse_cache`) and gives the same tree as a parse.
      ENTRIES = %w[machine/lower.rb prism_shim/prism/prism.rb].freeze

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
                  *files.flat_map { |source, path| [Paths.portable(path), source] })
      end

      #: () -> Array[String]
      def loads = Session.current.memo(:kernel_loads) { Digests.required(ENTRIES) }

      #: () -> String
      def loads_digest
        Session.current.memo(:kernel_loads_digest) do
          Digest::SHA256.new.tap do |d|
            loads.each { |name| d << name << "\0" << Digests.file(File.join(LIB, name)) << "\0" }
          end.hexdigest
        end
      end
    end
  end
end
