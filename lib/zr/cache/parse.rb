# frozen_string_literal: true

require "digest/sha2"
require_relative "../paths"
require_relative "../binary"
require_relative "../parse"
require_relative "../source_guard"
require_relative "store"
require_relative "../runtime/lib/zr/eval/runtime" if Zr::Binary.running?

module Zr
  module Cache
    # A cache of Prism.parse results, in the store (lib/zr/cache/store.rb) as
    # kind `parse`. A build reads back the parse of a
    # source that it parsed before. Marshal loads it about 40 times faster
    # than the port parses a file in a new process.
    #
    # The key covers every input of a parse: the source bytes, the options,
    # ruby's version (Marshal's format), and the parser itself (the port's
    # files, the backend's, lib/zr/parse.rb, this file, and the prism gem's
    # Ruby part). A cache file that does not load as a ParseResult is a
    # miss. A cached result has the same values as a parse, but its Strings
    # are not frozen.
    #
    # Under ruby, the parser is the files on disk. A compiled compiler
    # parses with the files it was built from, and contains their digests.
    # So a binary from a different tree uses different keys. The two file
    # sets differ (the binary contains only the gem files that the port
    # loads), so ruby and a binary never share a parse.
    module Parse
      # The files of the parser: these, and every Ruby file under the trees.
      GEM = Library::Ports.lib("prism") #: String
      FILES = [File.join(Library::Layout::EXT, "prism/prism.rb"), File.expand_path("../parse.rb", __dir__), __FILE__,
               File.join(GEM, "prism.rb")].freeze #: Array[String]
      TREES = [File.join(Library::Layout::EXT, "prism/ruby"), File.expand_path("../prism_shim", __dir__),
               File.join(GEM, "prism")].freeze #: Array[String]

      # The maximum source bytes whose parses a process keeps. A tree in
      # memory is tens of times the size of its source, so this is only a
      # proxy. Its purpose is to set a limit.
      MEMO_BYTES = 4 * 1024 * 1024

      # The parses that this process made or read back, with the same keys
      # as the cache files, newest last. It is an LRU with a size limit.
      #
      # All callers share one result. This is safe because a ParseResult is
      # written once and then only read: the port's setters
      # (lib/zr/runtime/ext/prism/ruby/mutation.rb) run while it builds the tree,
      # and no later code writes to a node.
      #
      # The limit is necessary for both users. A test tier worker runs
      # about a hundred examples that each require "set", so the memo must
      # keep set.rb's tree. A build parses each file only once, so an
      # unlimited memo only keeps every tree until the build ends. For a
      # self-compile, that is gigabytes that the collector marks on each pass.
      class Memo
        # @rbs @bound: Integer
        # @rbs @held: Hash[String, Held]

        # A parse in the memo, and the bytes that it counts against the limit.
        class Held
          attr_reader :result #: Prism::ParseResult
          attr_reader :bytes #: Integer

          #: (result: Prism::ParseResult, bytes: Integer) -> void
          def initialize(result:, bytes:)
            @result = result
            @bytes = bytes
            freeze
          end
        end

        #: (Integer bound) -> void
        def initialize(bound)
          @bound = bound
          @held = {}
          @bytes = 0
        end

        # The total source bytes of the parses in the memo.
        attr_reader :bytes #: Integer

        # The result under `key`, made the most recently used, or nil.
        #: (String key) -> Prism::ParseResult?
        def [](key)
          held = @held.delete(key) or return nil

          @held[key] = held
          held.result
        end

        # Keeps `result` under `key`, and drops the least recently used
        # entries until the total is in the limit. It returns but does not
        # keep a source larger than the limit, so one big file cannot empty
        # the memo.
        #: (String key, Prism::ParseResult result, Integer bytes) -> Prism::ParseResult
        def keep(key, result, bytes)
          return result if bytes > @bound

          @bytes += bytes - (@held.delete(key)&.bytes || 0)
          @held[key] = Held.new(result: result, bytes: bytes)
          drop_oldest while @bytes > @bound
          result
        end

        #: () -> void
        def clear
          @held.clear
          @bytes = 0
        end

        private

        #: () -> void
        def drop_oldest
          oldest = @held.shift or raise "memo: no entry to drop"
          @bytes -= oldest[1].bytes
        end
      end

      module_function

      #: (String source, **untyped options) -> Prism::ParseResult
      def parse(source, **options)
        key = key(source, options)
        memo[key] || memo.keep(key, parsed(key, source, options), source.bytesize)
      end

      # The parse for `key`: from an earlier build's entry, else a new parse
      # by the port, kept for the next build. A read counts as a use, so
      # eviction keeps the parses that builds read.
      #: (String key, String source, Hash[Symbol, untyped] options) -> Prism::ParseResult
      def parsed(key, source, options)
        cached = Store.read(:parse, key)
        return cached if cached.is_a?(Prism::ParseResult)

        Prism.parse(source, **options).tap { |result| keep(:parse, key, result) }
      end

      # The parses that this process keeps.
      #: () -> Memo
      def memo
        Session.current.memo(:parse_memo) { Memo.new(MEMO_BYTES) }
      end

      #: (String source, Hash[Symbol, untyped] options) -> String
      def key(source, options)
        Digest::SHA256.new.tap { |digest| digest << parser << "\0" << options.inspect << "\0" << source }.hexdigest
      end

      # The digest of the parser, computed once per process.
      #: () -> String
      def parser = Session.current.memo(:parser_key) { parser_key(parser_digests) }

      # The stamp of each parser file, and of each maker file, when this
      # process took its digest; `keep` checks them again. Empty in a
      # compiled compiler, which carries the digests and not the files.
      #: () -> Hash[String, [Rational, Integer]?]
      def stamps = Session.current.memo(:parser_stamps) { {} }

      # One digest of ruby's version and each parser file (its path and its
      # own digest).
      #: (Hash[String, String] digests) -> String
      def parser_key(digests)
        Digest::SHA256.new.tap do |digest|
          digest << RUBY_VERSION << "\0"
          digests.sort.each { |file, sha| digest << file << "\0" << sha << "\0" }
        end.hexdigest
      end

      # Each parser file, with the SHA-256 of its bytes. Under ruby, it also
      # records each file stamp (`stamps`).
      #: () -> Hash[String, String]
      def parser_digests
        return ::Zr::Eval::Runtime.sources.select { |path, _| parser_file?(path) } if Binary.running?

        files = parser_files
        stamps.merge!(files.to_h { |file| [file, Paths.stamp(file)] })
        files.to_h { |file| [file, Digest::SHA256.hexdigest(File.binread(file))] }
      end

      # A cached String derived from the tree of `source` (the block's
      # result), kept next to its parse. Its key is the parse key, `kind`,
      # and the digest of `files` (the code that derives it). If a file has
      # no digest, it returns the block's result and caches nothing.
      #: (String kind, String source, Hash[Symbol, untyped] options, Array[String] files) { () -> String } -> String
      def derived(kind, source, options, files)
        maker = maker(files) or return yield

        key = Store.key(key(source, options), kind, maker)
        text = Store.read(:derived, key)&.force_encoding(Encoding::UTF_8)
        return text if text&.valid_encoding?

        yield.tap { |made| keep(:derived, key, made.b) }
      end

      # One digest of `files` (the code that derives a cached form), or nil
      # if one of the files is missing. Under ruby, the files' stamps are
      # added to the parser's stamps (`stamps`).
      #: (Array[String] files) -> String?
      def maker(files)
        makers = Session.current.memo(:parse_makers) { {} } #: Hash[Array[String], String?]
        return makers[files] if makers.key?(files)

        digests = if Binary.running?
                    carried = ::Zr::Eval::Runtime.sources
                    files.to_h { |file| [file, carried[file]] }
                  else
                    files.to_h { |file| [file, (Digest::SHA256.hexdigest(File.binread(file)) if File.file?(file))] }
                  end
        parser
        stamps.merge!(files.to_h { |file| [file, Paths.stamp(file)] }) unless Binary.running?
        # `all?` makes sure that each digest is a String.
        whole = digests #: Hash[String, String]
        makers[files] = (parser_key(whole) if digests.values.all?)
      end

      # The parser files on disk.
      #: () -> Array[String]
      def parser_files
        (FILES.select { |file| File.file?(file) } + TREES.flat_map { |tree| Dir[File.join(tree, "**/*.rb")] }).uniq.sort
      end

      # Checks the path only, because a compiled compiler has the digests but
      # not the files.
      #: (String path) -> bool
      def parser_file?(path)
        FILES.include?(path) || (path.end_with?(".rb") && TREES.any? { |tree| path.start_with?("#{tree}/") })
      end

      # Keeps `value` as the entry `key` of `kind` (`:parse` or `:derived`).
      # Keeps nothing if a source changed during the build
      # (`SourceGuard.check!`), or if a parser file changed after its
      # digest: this process parses with the code that it loaded, but the
      # key names the files on disk.
      #: (Symbol kind, String key, untyped value) -> void
      def keep(kind, key, value)
        moved = stamps.find { |file, was| Paths.stamp(file) != was }
        raise SourceChanged, "#{moved.first} changed while this build ran; nothing it parsed is kept" if moved

        Store.write(kind, key, value)
      end
    end
  end
end
