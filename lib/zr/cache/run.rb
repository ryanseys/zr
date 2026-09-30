# frozen_string_literal: true

require "digest/sha2"
require_relative "../config"
require_relative "../paths"
require_relative "../settled"
require_relative "../runtime_sources"
require_relative "store"
require_relative "../version"

module Zr
  module Cache
    # The binaries that `zr run` built, kept so that a second run of the
    # same program runs at once, with no lowering and no link. Each is a
    # directory entry of the store (kind `run`), which keeps them under
    # its quota: a binary with eval support is 130 MB.
    #
    # An entry is found by a digest of what a build reads before it knows
    # which files the program requires: zr's version, the runtime and link
    # digests, the target, the path root, the settings that change a
    # build's bytes, the link arguments, and the program's path and bytes.
    # The entry then lists every file that the build compiled, with the
    # digest of its bytes, and the key of eval support for a program that
    # evals. A hit needs each of them to be the same now, so an edit to a
    # required file is a miss, as a make rule would see it.
    #
    # The binary runs from the cache. A new file is slow to start the first
    # time (macOS checks it: 61 ms against 11 ms), so a copy per run would
    # give most of that back.
    class Run
      VERSION = 1

      # `ZR_RUN_CACHE=0` builds each run again.
      def self.wanted? = Config.current.run_cache?

      # `digest` is the runtime's digest (`RuntimeSources#runtime_digest`). `gems` is the
      # build's GemSet: a program built with other gems is another entry,
      # also when the files of the first gems are still there.
      def initialize(input, target:, digest:, link:, gems: nil)
        @input = File.expand_path(input)
        config = Config.current
        @digest = digest
        @target = target
        @key = Store.key(VERSION, Zr::VERSION, digest, Digests.link, target.triple, Paths.root.to_s,
                         config.linker, config.eval_walk?, config.verify?, *link, "\0", gems && !gems.empty? ? gems.digest : "",
                         @input, File.binread(@input))
      end

      # The path of the kept binary when every file it was built from is as
      # it was, else nil.
      def hit
        entry = Store.read(:run, @key) or return nil
        binary = File.join(entry, "program")
        sources = Marshal.load(File.binread(File.join(entry, "sources")))
        File.executable?(binary) && current?(sources) ? binary : nil
      rescue SystemCallError, TypeError, ArgumentError, EOFError
        nil
      end

      # Keeps the binary at `out`, built from `program`, and returns the path
      # of the kept binary. It keeps nothing, and returns nil, when a source
      # changed during the build (`Zr.moved`), when the build does not know
      # its sources, or when the binary spells the build directory `work`,
      # which a later run would not have.
      def keep(out, program, work)
        return if program.sources.empty? || Zr.moved
        return if File.binread(out).include?(work)

        sources = program.sources.dup
        sources[:eval] = [program.evals.meta_path, program.evals.key] if program.evals
        entry = Store.write(:run, @key) do |dir|
          kept(out, File.join(dir, "program"))
          File.binwrite(File.join(dir, "sources"), Marshal.dump(sources))
        end
        Store.evict(kinds: [:run])
        File.join(entry, "program")
      rescue SystemCallError, SourceChanged
        nil
      end

      private

      # Puts the binary at `to`: a second name for the same file where the
      # volume allows, else a copy. A copy of a binary with eval support
      # took 30 ms. The same file also keeps macOS's check of its code
      # signature, so the first run from the cache does not pay it again.
      def kept(out, to)
        File.link(out, to)
      rescue SystemCallError
        Paths.copy(out, to)
      end

      # Whether the eval support that the binary linked is still current: its
      # metadata has the same key (the same code), and its files are as that
      # metadata read them.
      def eval_current?(meta_path, key)
        require "json"
        meta = JSON.parse(File.read(meta_path))
        base = RuntimeSources.for(@target).eval_digest(@digest) or return false
        meta.fetch("key") == key && Digests.eval_files_key(base, meta.fetch("files"), {}, meta.fetch("absent", [])) == meta.fetch("files_key")
      rescue JSON::ParserError, KeyError, SystemCallError
        false
      end

      def current?(sources)
        sources.all? do |path, digest|
          if path == :eval
            eval_current?(*digest)
          else
            File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
          end
        end
      end
    end
  end
end
