# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"
require_relative "config"
require_relative "prism"
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
    # root, and each of `files` with its bytes (`bytes` has the ones that a
    # build already read, so it hashes what it lowered). A file of the
    # compiler counts by its code (`code`), so an edit of its comments
    # rebuilds nothing; the kernel and the core count by their bytes,
    # because a binary holds their line numbers.
    #: (Target target, Array[String] files, ?Hash[String, String] bytes) -> String
    def sources(target, files, bytes = {})
      Digest::SHA256.new.tap do |d|
        d << target.triple << "\0"
        d << "root\0" << Paths.root << "\0" if Paths.root
        d << "checked\0" if Config.current.kernel_checked?
        files.each do |path|
          data = bytes[path] || File.binread(path)
          d << path << "\0" << (compiler_file?(path) ? code_digest(data) : data)
        end
      end.hexdigest
    end

    COMPILER = File.join(__dir__, "") #: String

    # Whether `path` is a file of the compiler, not one that it compiles.
    #: (String path) -> bool
    def compiler_file?(path) = path.start_with?(COMPILER) && !path.start_with?(File.join(Paths::RUNTIME, ""))

    # The digest of `bytes` without their comments (`code`), kept in the
    # store by the digest of the bytes, so only a file that changed is
    # read again.
    #: (String bytes) -> String
    def code_digest(bytes)
      key = Digest::SHA256.hexdigest(bytes)
      Cache::Store.read(:source, key) || Digest::SHA256.hexdigest(code(bytes)).tap { |d| Cache::Store.write(:source, key, d) }
    rescue SourceChanged
      Digest::SHA256.hexdigest(code(bytes))
    end

    # The Ruby source `bytes` without its comments: a comment that is
    # the whole line goes with its line, and one after code goes with the
    # spaces before it. Prism finds the comments, so a `#` in a string
    # stays. A magic comment (`frozen_string_literal`) stays: it changes
    # what the code does.
    def code(bytes)
      out = bytes.b
      Prism.parse_comments(bytes).reverse_each do |comment|
        from = comment.location.start_offset
        to = comment.location.end_offset
        next if MAGIC.match?(out.byteslice(from, to - from))

        start = from.zero? ? 0 : (out.rindex("\n", from - 1) || -1) + 1
        if out.byteslice(start, from - start).strip.empty?
          from = start
          to += 1 if out.getbyte(to) == 10
        else
          from -= 1 while from > start && BLANKS.include?(out.getbyte(from - 1))
        end
        out = out.byteslice(0, from) + out.byteslice(to..)
      end
      out
    end

    # A space and a tab: the blanks before a comment after code.
    BLANKS = [32, 9].freeze #: Array[Integer]

    MAGIC = /\A#\s*(?:-\*-.*)?(?:frozen_string_literal|encoding|coding|warn_indent|warn_past_scope|shareable_constant_value)\s*:/i

    # The key of what eval support reads: the eval digest and the bytes of
    # each file (`EvalSupport#files_key`). `bytes` has the ones that a build
    # already read. `absent` lists the paths that must still not exist.
    #: (String eval_digest, Array[String] files, ?Hash[String, String] bytes, ?Array[String] absent) -> String
    def eval_files_key(eval_digest, files, bytes = {}, absent = [])
      Digest::SHA256.new.tap do |d|
        d << eval_digest
        files.each do |path|
          d << path << "\0" << (bytes[path] || (File.exist?(path) ? File.binread(path) : ""))
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
