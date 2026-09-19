# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "paths"

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
  module ParseCache
    def self.directory = File.join(Paths.cache, "parse")

    # The files a parse runs, beside the gem's Ruby half.
    OWN = [File.expand_path("../../rt/ext/prism/{prism.rb,ruby/**/*.rb}", __dir__), File.join(__dir__, "prism_backend/**/*.rb"),
           File.join(__dir__, "prism.rb"), __FILE__].freeze

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
      Held = Data.define(:result, :bytes)

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
    def parser
      @parser ||= Digest::SHA256.new.tap do |digest|
        digest << RUBY_VERSION << "\0"
        parser_files.each { |file| digest << file << "\0" << File.binread(file) << "\0" }
      end.hexdigest
    end

    # The files a parse runs. The gem's Ruby half is prism.rb where
    # require finds it and the files under prism/.
    def parser_files
      gem = $LOAD_PATH.resolve_feature_path("prism").last
      [gem, *Dir[File.join(File.dirname(gem), "prism/**/*.rb")], *OWN.flat_map { |pattern| Dir[pattern] }].uniq.sort
    end

    def read(path)
      result = Marshal.load(File.binread(path))
      result if result.is_a?(Prism::ParseResult)
    rescue SystemCallError, ArgumentError, TypeError, EOFError
      nil
    end

    # The file written whole: a parallel build never reads half of one.
    def write(path, bytes)
      FileUtils.mkdir_p(directory)
      fresh = "#{path}.#{Process.pid}.#{Thread.current.object_id}"
      File.binwrite(fresh, bytes)
      File.rename(fresh, path)
    end
  end
end
