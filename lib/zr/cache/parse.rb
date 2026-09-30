# frozen_string_literal: true

require "digest/sha2"
require_relative "../paths"
require_relative "../prism"
require_relative "../settled"
require_relative "store"
require_relative "../../../runtime/lib/zr/eval/runtime" unless Zr::HOSTED

module Zr
  module Cache
    # A cache of Prism.parse results, in the store (lib/zr/cache/store.rb) as
    # kind `parse`. A build reads back the parse of a
    # source that it parsed before. Marshal loads it about 40 times faster
    # than the port parses a file in a new process.
    #
    # The key covers every input of a parse: the source bytes, the options,
    # ruby's version (Marshal's format), and the parser itself (the port's
    # files, the backend's, lib/zr/prism.rb, this file, and the prism gem's
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
      GEM = Ports.lib("prism")
      FILES = [File.join(Layout::EXT, "prism/prism.rb"), File.expand_path("../prism.rb", __dir__), __FILE__, File.join(GEM, "prism.rb")].freeze
      TREES = [File.join(Layout::EXT, "prism/ruby"), File.expand_path("../prism_shim", __dir__), File.join(GEM, "prism")].freeze

      # The maximum source bytes whose parses a process keeps. A tree in
      # memory is tens of times the size of its source, so this is only a
      # proxy. Its purpose is to set a limit.
      MEMO_BYTES = 4 * 1024 * 1024

      # The parses that this process made or read back, with the same keys
      # as the cache files, newest last. It is an LRU with a size limit.
      #
      # All callers share one result. This is safe because a ParseResult is
      # written once and then only read: the port's setters
      # (runtime/ext/prism/ruby/mutation.rb) run while it builds the tree,
      # and no later code writes to a node.
      #
      # The limit is necessary for both users. A test tier worker runs
      # about a hundred examples that each require "set", so the memo must
      # keep set.rb's tree. A build parses each file only once, so an
      # unlimited memo only keeps every tree until the build ends. For a
      # self-compile, that is gigabytes that the collector marks on each pass.
      class Memo
        # A parse in the memo, and the bytes that it counts against the limit.
        class Held
          attr_reader :result, :bytes

          def initialize(result:, bytes:)
            @result = result
            @bytes = bytes
            freeze
          end
        end

        def initialize(bound)
          @bound = bound
          @held = {}
          @bytes = 0
        end

        # The total source bytes of the parses in the memo.
        attr_reader :bytes

        # The result under `key`, made the most recently used, or nil.
        def [](key)
          held = @held.delete(key) or return nil

          @held[key] = held
          held.result
        end

        # Keeps `result` under `key`, and drops the least recently used
        # entries until the total is in the limit. It returns but does not
        # keep a source larger than the limit, so one big file cannot empty
        # the memo.
        def keep(key, result, bytes)
          return result if bytes > @bound

          @bytes += bytes - (@held.delete(key)&.bytes || 0)
          @held[key] = Held.new(result: result, bytes: bytes)
          drop_oldest while @bytes > @bound
          result
        end

        def clear
          @held.clear
          @bytes = 0
        end

        private

        def drop_oldest
          _, held = @held.shift
          @bytes -= held.bytes
        end
      end

      module_function

      def parse(source, **options)
        key = key(source, options)
        memo[key] || memo.keep(key, parsed(key, source, options), source.bytesize)
      end

      # The parse for `key`: from an earlier build's cache file, else a new
      # parse by the port, written for the next build.
      def parsed(key, source, options)
        path = Store.path(:parse, "#{key}.marshal")
        read(path) || Prism.parse(source, **options).tap { |result| write(path, Marshal.dump(result)) }
      end

      # The parses that this process keeps.
      def memo
        @memo ||= Memo.new(MEMO_BYTES)
      end

      def key(source, options)
        Digest::SHA256.new.tap { |digest| digest << parser << "\0" << options.inspect.b << "\0" << source.b }.hexdigest
      end

      # The digest of the parser, computed once per process.
      def parser = @parser ||= parser_key(parser_digests)

      # One digest of ruby's version and each parser file (its path and its
      # own digest).
      def parser_key(digests)
        Digest::SHA256.new.tap do |digest|
          digest << RUBY_VERSION << "\0"
          digests.sort.each { |file, sha| digest << file << "\0" << sha << "\0" }
        end.hexdigest
      end

      # Each parser file, with the SHA-256 of its bytes. Under ruby, it also
      # records each file stamp, and `write` checks them again.
      def parser_digests
        return ::Zr::Eval::Runtime.sources.select { |path, _| parser_file?(path) } unless HOSTED

        files = parser_files
        @stamps = files.to_h { |file| [file, Paths.stamp(file)] }
        files.to_h { |file| [file, Digest::SHA256.hexdigest(File.binread(file))] }
      end

      # A cached String derived from the tree of `source` (the block's
      # result), kept next to its parse. Its key is the parse key, `kind`,
      # and the digest of `files` (the code that derives it). If a file has
      # no digest, it returns the block's result and caches nothing.
      def derived(kind, source, options, files)
        maker = maker(files) or return yield

        path = Store.path(:parse, "#{Store.key(key(source, options), kind, maker)}.#{kind}")
        text = File.binread(path).force_encoding(Encoding::UTF_8) if File.file?(path)
        return text if text&.valid_encoding?

        yield.tap { |made| write(path, made.b) }
      end

      # One digest of `files` (the code that derives a cached form), or nil
      # if one of the files is missing. Under ruby, the files' stamps are
      # added to the parser's stamps, and `write` checks them again.
      def maker(files)
        @makers ||= {}
        return @makers[files] || nil if @makers.key?(files)

        digests = if HOSTED
                    files.to_h { |file| [file, File.file?(file) && Digest::SHA256.hexdigest(File.binread(file))] }
                  else
                    carried = ::Zr::Eval::Runtime.sources
                    files.to_h { |file| [file, carried[file]] }
                  end
        parser
        @stamps&.merge!(files.to_h { |file| [file, Paths.stamp(file)] })
        @makers[files] = digests.values.all? && parser_key(digests)
        @makers[files] || nil
      end

      # The parser files on disk.
      def parser_files
        (FILES.select { |file| File.file?(file) } + TREES.flat_map { |tree| Dir[File.join(tree, "**/*.rb")] }).uniq.sort
      end

      # Checks the path only, because a compiled compiler has the digests but
      # not the files.
      def parser_file?(path)
        FILES.include?(path) || (path.end_with?(".rb") && TREES.any? { |tree| path.start_with?("#{tree}/") })
      end

      def read(path)
        result = Marshal.load(File.binread(path))
        result if result.is_a?(Prism::ParseResult)
      rescue SystemCallError, ArgumentError, TypeError, EOFError
        nil
      end

      # Writes the file atomically, so a parallel build never reads half of
      # it. Writes nothing if a source changed during the build
      # (`Zr.settled!`), or if a parser file changed after its digest. This
      # process parses with the code that it loaded, but the key identifies
      # the files on disk.
      def write(path, bytes)
        moved = (@stamps || {}).find { |file, was| Paths.stamp(file) != was }
        raise SourceChanged, "#{moved.first} changed while this build ran; nothing it parsed is kept" if moved

        Store.write_file(path, bytes)
      end
    end
  end
end
