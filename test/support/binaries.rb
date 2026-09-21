# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/obj/macho/skeleton"

module Ze0
  module Spec
    # The binaries the examples built, kept for the next run.
    #
    # An example is a build and a run, and on a warm cache the build is
    # three quarters of it. A run after an edit that reached no part of
    # the compiler -- a spec's own sentence, a fixture, a test file --
    # builds every example again to the same bytes, since a build is a
    # function of its inputs and `rake stage1` proves it. `ZE0_BINARIES=1`
    # keeps each example's binary under the cache, named by every input
    # of its bytes, and a later run takes the binary and skips to the
    # run. It is asked for and not on: seven thousand binaries are tens
    # of gigabytes even with their text cloned, and `rake cache:prune`
    # sweeps them by age like the rest.
    #
    # The key fails closed. It holds the runtime's digest for the target
    # (everything that lowers and emits the runtime), the link digest,
    # the target, the environment names that reach a build's bytes, the
    # program's path and source, and every fixture written beside it,
    # a link by where it points. An example that writes no key -- one
    # whose fixtures this cannot describe -- is built as before.
    module Binaries
      VERSION = 1
      # The environment a build reads that decides its bytes.
      ENVIRONMENT = %w[ZE0_LINK ZE0_EVAL ZE0_WASM_NAMES ZE0_WASM_WIDTH].freeze

      module_function

      def asked? = ENV["ZE0_BINARIES"] == "1"

      def directory = File.join(Zr.cache, "binaries")

      # Where the binary of this example is kept, or nil where no key
      # can describe it.
      def path(target, source, rb, files)
        parts = files.sort.map { |name, bytes| [name, bytes.is_a?(Hash) ? "-> #{bytes.fetch(:symlink)}" : bytes] }
        return nil unless parts.all? { |_, bytes| bytes.is_a?(String) }

        key = Digest::SHA256.new
        [VERSION, Zr.runtime(target).digest, Zr.link_digest, target.triple,
         *ENVIRONMENT.map { |name| ENV[name].to_s }, rb, source, *parts.flatten].each { |part| key << part.to_s << "\0" }
        File.join(directory, "#{key.hexdigest}#{'.wasm' unless target.link}")
      end

      # The kept binary at `bin`, or false where there is none.
      def take(kept, bin)
        return false unless kept && File.exist?(kept)

        copy(kept, bin)
        true
      end

      # `bin` kept whole: copied beside its place, then named.
      def keep(kept, bin)
        return unless kept

        FileUtils.mkdir_p(directory)
        tmp = "#{kept}.#{Process.pid}"
        copy(bin, tmp)
        File.rename(tmp, kept)
      end

      # A clone where the filesystem clones -- a kept binary then shares
      # its runtime's blocks with the skeleton it was cloned from, and
      # costs the few megabytes that are its own -- else a copy.
      def copy(from, to)
        Obj::MachO::Skeleton.clone(from, to, File.size(from)) || FileUtils.cp(from, to)
      end
    end
  end
end
