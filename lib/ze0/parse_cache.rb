# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"
require_relative "prism"
require "ze0/eval/runtime" unless Ze0::HOSTED

module Ze0
  # Prism.parse's results kept in the cache: a build reads back the parse
  # of a source it has parsed before, which Marshal loads some forty times
  # faster than the port parses a file in a fresh process.
  #
  # The key covers every input of a parse: the source's bytes, the options,
  # ruby's version (Marshal's format), and the parser itself, which is the
  # port's files, the backend's, lib/ze0/prism.rb and this file, and the
  # prism gem's Ruby half. A cache file that does not load back as a
  # ParseResult is a miss. A result read back holds the same values as a
  # parse, though its Strings are not frozen.
  #
  # Under ruby the parser is the files on disk. A compiled compiler
  # parses with the files it was built from, and carries their digests,
  # so a binary built from another tree keys its parses apart and never
  # answers for this one. The two sets differ (the binary holds only the
  # gem files the port loads), so the two never share a parse.
  module ParseCache
    def self.directory = File.join(Paths.cache, "parse")

    # The files a parse runs: these, and every Ruby file under the trees.
    GEM = File.join(Paths::VENDOR, "ext/prism/lib")
    FILES = [File.join(Paths::RT, "ext/prism/prism.rb"), File.join(__dir__, "prism.rb"), __FILE__, File.join(GEM, "prism.rb")].freeze
    TREES = [File.join(Paths::RT, "ext/prism/ruby"), File.join(__dir__, "prism_backend"), File.join(GEM, "prism")].freeze

    # The source bytes whose parses a process keeps. A tree in memory is
    # some tens of times its source, so this is a proxy and not a
    # measurement; what it has to be is a bound.
    MEMO_BYTES = 4 * 1024 * 1024

    # The parses this process has made or read back, keyed as the cache
    # files are, newest last, and bounded: past the bound the least
    # recently asked for goes first.
    #
    # One result answers every caller. That is sound because a
    # ParseResult is written once and read after: the port's setters
    # (rt/ext/prism/ruby/mutation.rb) run while it builds the tree, and
    # nothing downstream writes to a node.
    #
    # The bound is what makes the memo pay in both of the shapes that ask
    # for it. A worker of the test tier runs a hundred examples that each
    # require "set", and unmarshalling set.rb's tree a hundred times is
    # the whole of what that costs -- so there the memo must hold. A
    # build parses each file exactly once, so there it can only retain,
    # and an unbounded one holds every tree of the program until the
    # build ends, which a self-compile pays for in gigabytes the
    # collector marks on every pass.
    class Memo
      # A parse the memo holds, and the bytes it counts against the bound.
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

      # What is held for source of this many bytes.
      attr_reader :bytes

      # The result under `key`, made the most recently used, or nil.
      def [](key)
        held = @held.delete(key) or return nil

        @held[key] = held
        held.result
      end

      # `result` held under `key`, and the least recently used dropped
      # until what is held is inside the bound. A source larger than the
      # whole bound is answered and not held, so one big file cannot
      # empty the memo.
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

    # The parse under `key`: what an earlier build left in the cache, else
    # the port's, whose answer the next build reads back.
    def parsed(key, source, options)
      path = File.join(directory, "#{key}.marshal")
      read(path) || Prism.parse(source, **options).tap { |result| write(path, Marshal.dump(result)) }
    end

    # The parses this process holds.
    def memo
      @memo ||= Memo.new(MEMO_BYTES)
    end

    def key(source, options)
      Digest::SHA256.new.tap { |digest| digest << parser << "\0" << options.inspect.b << "\0" << source.b }.hexdigest
    end

    # The digest of what a parse runs, made once a process.
    def parser = @parser ||= parser_key(parser_digests)

    # One digest of ruby's version and each file a parse runs, by its
    # path and its own digest.
    def parser_key(digests)
      Digest::SHA256.new.tap do |digest|
        digest << RUBY_VERSION << "\0"
        digests.sort.each { |file, sha| digest << file << "\0" << sha << "\0" }
      end.hexdigest
    end

    # Each file a parse runs, with the SHA-256 of its bytes. Under ruby
    # the stamp of each is kept too, and a write checks them again
    # (`write`).
    def parser_digests
      return Ze0::Eval::Runtime.sources.select { |path, _| parser_file?(path) } unless HOSTED

      files = parser_files
      @stamps = files.to_h { |file| [file, stamp(file)] }
      files.to_h { |file| [file, Digest::SHA256.hexdigest(File.binread(file))] }
    end

    # What `kind` makes of the tree of `source` under `options`, kept
    # beside its parse: the String the block answers, under the parse's
    # own key and the digest of `files`, the code that makes it. Nil
    # where a file has no digest to take, and the block's answer alone.
    def derived(kind, source, options, files)
      maker = maker(files) or return yield

      path = File.join(directory, "#{Digest::SHA256.hexdigest("#{key(source, options)}\0#{kind}\0#{maker}")}.#{kind}")
      text = File.binread(path).force_encoding(Encoding::UTF_8) if File.file?(path)
      return text if text&.valid_encoding?

      yield.tap { |made| write(path, made.b) }
    end

    # One digest of `files`, the code that derives a cached form; nil
    # where one of them is not there to digest. Under ruby the files'
    # stamps join the parser's, which a write checks again.
    def maker(files)
      @makers ||= {}
      return @makers[files] || nil if @makers.key?(files)

      digests = if HOSTED
                  files.to_h { |file| [file, File.file?(file) && Digest::SHA256.hexdigest(File.binread(file))] }
                else
                  carried = Ze0::Eval::Runtime.sources
                  files.to_h { |file| [file, carried[file]] }
                end
      parser
      @stamps&.merge!(files.to_h { |file| [file, stamp(file)] })
      @makers[files] = digests.values.all? && parser_key(digests)
      @makers[files] || nil
    end

    # The files on disk a parse runs.
    def parser_files
      (FILES.select { |file| File.file?(file) } + TREES.flat_map { |tree| Dir[File.join(tree, "**/*.rb")] }).uniq.sort
    end

    # By the path alone: a compiled compiler has its digests, not the files.
    def parser_file?(path)
      FILES.include?(path) || (path.end_with?(".rb") && TREES.any? { |tree| path.start_with?("#{tree}/") })
    end

    # What a file is as far as a stat says, or nil for one that is gone.
    def stamp(file)
      stat = File.stat(file)
      [stat.mtime.to_r, stat.size]
    rescue SystemCallError
      nil
    end

    def read(path)
      result = Marshal.load(File.binread(path))
      result if result.is_a?(Prism::ParseResult)
    rescue SystemCallError, ArgumentError, TypeError, EOFError
      nil
    end

    # The file written whole: a parallel build never reads half of one;
    # nothing while a source has moved under the build (`Zr.settled!`),
    # or a file of the parser since its digest was taken: this process
    # parses with the code it loaded, and the key names what is on disk.
    def write(path, bytes)
      Zr.settled! if defined?(Zr)
      moved = (@stamps || {}).find { |file, was| stamp(file) != was }
      raise (defined?(Zr::Moved) ? Zr::Moved : RuntimeError), "#{moved.first} changed while this build ran; nothing it parsed is kept" if moved

      Paths.mkdir_p(directory)
      fresh = "#{path}.#{Process.pid}.#{Thread.current.object_id}"
      File.binwrite(fresh, bytes)
      File.rename(fresh, path)
    end
  end
end
