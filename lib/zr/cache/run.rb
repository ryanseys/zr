# frozen_string_literal: true

require "digest/sha2"
require "json"
require_relative "../config"
require_relative "../paths"
require_relative "../source_guard"
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
    # build's bytes, the link arguments, the program's path (both as given,
    # which the binary shows as `__FILE__` and in backtraces, and expanded)
    # and bytes, and
    # its ruby switches (`Hir::Switches`). A program from -e or standard
    # input has no file: its text is in the key.
    # The entry then lists every file that the build compiled, with the
    # digest of its bytes, and the key of eval support for a program that
    # evals. A hit needs each of them to be the same now, so an edit to a
    # required file is a miss, as a make rule would see it. The entry also
    # names the binary's SHA-256, size, inode and mtime: a hit runs only
    # the binary that zr kept. When the stat is the same, the hash is not
    # read again (46 ms for a 39 MB binary).
    #
    # The binary runs from the cache. A new file is slow to start the first
    # time (macOS checks it: 61 ms against 11 ms), so a copy per run would
    # give most of that back.
    class Run
      # @rbs @input: String
      # @rbs @digest: String
      # @rbs @target: Target
      # @rbs @key: String

      VERSION = 3

      # `ZR_RUN_CACHE=0` builds each run again.
      #: () -> bool
      def self.wanted? = Config.current.run_cache?

      # `digest` is the runtime's digest (`RuntimeSources#runtime_digest`). `gems` is the
      # build's GemSet: a program built with other gems is another entry,
      # also when the files of the first gems are still there. A build with
      # another require gate (`gate`: a require that no file answers stops
      # the build, or raises LoadError when it runs) or with its trace
      # events armed (`trace`) is another entry too. `source` is the
      # program's text, `input`'s bytes unless given.
      # @rbs input: String
      # @rbs target: Target
      # @rbs digest: String
      # @rbs link: Array[String]
      # @rbs source: String?
      # @rbs switches: Hir::Switches?
      # @rbs gems: GemSet?
      # @rbs gate: bool | :warn
      # @rbs trace: bool
      # @rbs return: void
      def initialize(input, target:, digest:, link:, source: nil, switches: nil, gems: nil, gate: true, trace: false)
        @input = File.expand_path(input)
        config = Config.current
        @digest = digest
        @target = target
        @key = Store.key(VERSION, Zr::VERSION, digest, Digests.link, target.triple, Paths.root.to_s,
                         config.linker, config.eval_walk?, config.verify?, gate, trace, *link, "\0", gems && !gems.empty? ? gems.digest : "",
                         input, @input, source&.b || File.binread(@input), switches&.key.to_s)
      end

      # The path of the kept binary when every file it was built from is as
      # it was, else nil.
      #: () -> String?
      def hit
        entry = Store.read(:run, @key) or return nil
        binary = File.join(entry, "program")
        sources = JSON.parse(File.read(File.join(entry, "sources")))
        kept?(binary, sources.fetch("program")) && current?(sources) ? binary : nil
      rescue SystemCallError, JSON::ParserError, KeyError, TypeError
        nil
      end

      # Keeps the binary at `out`, built from `program`, and returns the path
      # of the kept binary. It keeps nothing, and returns nil, when a source
      # changed during the build (`SourceGuard.changed_file`), when the build does not know
      # its sources, or when the binary spells the build directory `work`,
      # which a later run would not have.
      #: (String out, Program program, String work) -> String?
      def keep(out, program, work)
        given = program.sources or return
        return if SourceGuard.changed_file

        bytes = File.binread(out)
        return if bytes.include?(work)

        evals = program.evals
        entry = Store.write(:run, @key) do |dir|
          binary = File.join(dir, "program")
          kept(out, binary)
          sources = { "files" => given, "eval" => evals && [evals.meta_path, evals.key],
                      "program" => stamp(binary).merge("sha256" => Digest::SHA256.hexdigest(bytes)) }
          File.write(File.join(dir, "sources"), JSON.generate(sources))
        end
        Store.evict(kinds: [:run])
        File.join(entry, "program")
      rescue SystemCallError, SourceChanged
        nil
      end

      private

      # The stat of the kept binary that a hit compares: its size, inode and
      # mtime in nanoseconds. Not its ctime: the removal of the build's
      # second name for the file changes that.
      #: (String binary) -> Hash[String, Integer]
      def stamp(binary)
        stat = File.lstat(binary)
        { "size" => stat.size, "ino" => stat.ino, "mtime" => (stat.mtime.to_r * 1_000_000_000).to_i }
      end

      # Whether `binary` is the file that zr kept: a regular file of this
      # user that runs, with the stat that zr recorded, or else the same
      # SHA-256.
      #: (String binary, Hash[String, untyped] program) -> bool
      def kept?(binary, program)
        stat = File.lstat(binary)
        return false unless stat.file? && stat.owned? && stat.executable?
        return true if stamp(binary) == program.slice("size", "ino", "mtime")

        stat.size == program.fetch("size") && Digest::SHA256.file(binary).hexdigest == program.fetch("sha256")
      end

      # Puts the binary at `to`: a second name for the same file where the
      # volume allows, else a copy. A copy of a binary with eval support
      # took 30 ms. The same file also keeps macOS's check of its code
      # signature, so the first run from the cache does not pay it again.
      #: (String out, String to) -> void
      def kept(out, to)
        File.link(out, to)
      rescue SystemCallError
        Paths.copy(out, to)
      end

      # Whether the eval support that the binary linked is still current: its
      # metadata has the same key (the same code), and its files are as that
      # metadata read them.
      #: (String meta_path, String key) -> bool
      def eval_current?(meta_path, key)
        require "json"
        meta = JSON.parse(File.read(meta_path))
        base = RuntimeSources.for(@target).eval_digest(@digest) or return false
        none = [] #: Array[String]
        # The metadata keeps its paths portable (`EvalSupport#moved`).
        files = meta.fetch("files").map { |path| Paths.local(path) }
        absent = meta.fetch("absent", none).map { |path| Paths.local(path) }
        meta.fetch("key") == key && Digests.eval_files_key(base, files, {}, absent) == meta.fetch("files_key")
      rescue JSON::ParserError, KeyError, SystemCallError
        false
      end

      # (JSON gives `sources`, so its keys and values are not checked.)
      #: (Hash[String, untyped] sources) -> bool
      def current?(sources)
        meta_path, key = sources["eval"]
        return false if meta_path && !eval_current?(meta_path, key)

        sources.fetch("files").all? { |path, digest| File.file?(path) && Digest::SHA256.file(path).hexdigest == digest }
      end
    end
  end
end
