# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"
require_relative "config"
require_relative "parse"
require_relative "cache/store"

module Zr
  # The digests that name the cache's entries and that do not belong to
  # one target's sources (`RuntimeSources` has those).
  module Digests
    module_function

    # One digest of the LINK_ONLY files. A cache that the link writes
    # includes this digest in its name, with its other inputs.
    #: () -> String
    def link
      require_relative "runtime_sources"
      Session.current.memo(:link_digest) do
        Digest::SHA256.new.tap { |d| RuntimeSources::LINK_ONLY.each { |path| d << path << "\0" << File.binread(path) } }.hexdigest
      end
    end

    # The digest that names a runtime's cache files: the target, the path
    # root, and each of `files` with its own digest (`file`), taken at its
    # stamp in `stamps` (else at its stamp now). A build checks the stamps
    # again before it keeps anything (`Runtime#moved`).
    #: (Target target, Array[String] files, ?Hash[String, [Rational, Integer]?] stamps) -> String
    def sources(target, files, stamps = {})
      Digest::SHA256.new.tap do |d|
        d << target.triple << "\0"
        if (root = Paths.root)
          d << "root\0" << root << "\0"
        end
        d << "checked\0" if Config.current.kernel_checked?
        files.each { |path| d << path << "\0" << file(path, stamps.fetch(path) { Paths.stamp(path) }) }
      end.hexdigest
    end

    # The digest of `path` as `sources` counts it: a file of the compiler
    # by its code (`code_digest`), so an edit of its comments rebuilds
    # nothing, and the kernel, the core and the gem prelude by their bytes,
    # because a binary holds their line numbers. A process reads and
    # hashes each file once for each stamp it sees.
    #: (String path, ?[Rational, Integer]? stamp) -> String
    def file(path, stamp = Paths.stamp(path))
      Session.current.memo([:file_digest, path, stamp]) do
        bytes = File.binread(path)
        compiler_file?(path) ? code_digest(bytes) : Digest::SHA256.hexdigest(bytes)
      end
    end

    COMPILER = File.join(__dir__, "") #: String

    # Whether `path` is a file of the compiler, not one that it compiles.
    #: (String path) -> bool
    def compiler_file?(path) = path.start_with?(COMPILER) && !path.start_with?(File.join(Paths::RUNTIME, ""))

    # The digest of `bytes` without their comments (`code`), kept in the
    # store by the digest of the bytes, so only a file that changed is
    # read again. With `lines`, the digest of the code with its lines.
    #: (String bytes, ?lines: bool) -> String
    def code_digest(bytes, lines: false)
      key = Digest::SHA256.hexdigest(bytes)
      key = Digest::SHA256.hexdigest("lines\0#{key}") if lines
      Cache::Store.read(:source, key) || Digest::SHA256.hexdigest(code(bytes, lines: lines)).tap { |d| Cache::Store.write(:source, key, d) }
    rescue SourceChanged
      Digest::SHA256.hexdigest(code(bytes, lines: lines))
    end

    # The Ruby source `bytes` without its comments: a comment that is
    # the whole line goes with its line, and one after code goes with the
    # spaces before it. Prism finds the comments, so a `#` in a string
    # stays. A magic comment (`frozen_string_literal`) stays: it changes
    # what the code does. With `lines`, each line stays, so the code
    # keeps its line numbers: a comment leaves only its line breaks.
    #: (String bytes, ?lines: bool) -> String
    def code(bytes, lines: false)
      out = String.new(capacity: bytes.bytesize, encoding: Encoding::BINARY)
      kept = 0
      Prism.parse_comments(bytes).each do |comment|
        from = comment.location.start_offset
        to = comment.location.end_offset
        next if MAGIC.match?(bytes.byteslice(from, to - from))

        start = from.zero? ? 0 : (bytes.byterindex("\n", from - 1) || -1) + 1
        if blank?(bytes, start, from)
          from = start
          to += 1 if !lines && bytes.getbyte(to) == 10
        else
          from -= 1 while from > start && BLANKS.include?(bytes.getbyte(from - 1))
        end
        out << piece(bytes, kept, from)
        # A comment of many lines (=begin) keeps its line breaks.
        out << ("\n" * piece(bytes, from, to).count("\n")) if lines
        kept = to
      end
      out << piece(bytes, kept, bytes.bytesize)
    end

    # The bytes of `bytes` from `from` to `to`, which are in range.
    #: (String bytes, Integer from, Integer to) -> String
    def piece(bytes, from, to) = bytes.byteslice(from, to - from) #: String

    # Whether the bytes of `bytes` from `from` to `to` are only what
    # `strip` removes: the line before a comment that is the whole line.
    #: (String bytes, Integer from, Integer to) -> bool
    def blank?(bytes, from, to)
      from += 1 while from < to && STRIPPED.include?(bytes.getbyte(from))
      from == to
    end

    # A space and a tab: the blanks before a comment after code.
    BLANKS = [32, 9].freeze #: Array[Integer]
    # The bytes that String#strip removes.
    STRIPPED = [0, 9, 10, 11, 12, 13, 32].freeze #: Array[Integer]
    private_class_method :blank?, :piece

    MAGIC = /\A#\s*(?:-\*-.*)?(?:frozen_string_literal|encoding|coding|warn_indent|warn_past_scope|shareable_constant_value)\s*:/i

    # The key of what eval support reads: the eval digest and each file
    # (`EvalSupport#files_key`). `bytes` has the ones that a build already
    # read. `absent` lists the paths that must still not exist. A compiler
    # file counts by its code with its lines (`code`): eval support holds
    # the line numbers of what it compiles, but not the comments. So an
    # edit of a comment that keeps the lines keeps eval support.
    #: (String eval_digest, Array[String] files, ?Hash[String, String] bytes, ?Array[String] absent) -> String
    def eval_files_key(eval_digest, files, bytes = {}, absent = [])
      Digest::SHA256.new.tap do |d|
        d << eval_digest << "\0lines"
        files.each do |path|
          source = bytes[path] || (File.exist?(path) ? File.binread(path) : "")
          d << path << "\0" << (compiler_file?(path) ? code_digest(source, lines: true) : source)
        end
        # The paths where a feature that the lowering stopped on would be:
        # each one that exists now changes the key. `absent` names the form
        # of the key, so a key from before the paths counted is stale.
        d << "\0absent"
        absent.each { |path| d << "\0" << path if File.exist?(path) }
      end.hexdigest
    end

    # The key of an eval support object and of its symbol table: the key of
    # its files, and the names and site count that numbered its data. Two
    # tables number the same data to other words, so they must never share
    # a key.
    #: (String files_key, Array[String?] names, Integer sites) -> String
    def eval_key(files_key, names, sites)
      Digest::SHA256.new.tap do |d|
        d << files_key << "\0" << sites.to_s
        # Each name with its length, so no name can look like two; a pad
        # (nil) has no length.
        names.each { |name| d << (name.nil? ? "\0-" : "\0#{name.bytesize}:#{name}") }
      end.hexdigest
    end
  end
end
