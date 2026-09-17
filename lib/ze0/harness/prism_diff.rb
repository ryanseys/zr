# frozen_string_literal: true

require "fileutils"
require "prism"

module Ze0
  module Harness
    # The pure-Ruby prism (rt/ext/prism/ruby) held to ruby's
    # own C prism, file by file, with ruby as the only oracle.
    #
    # `writer` proves Prism::Ruby::Dump before a parser exists: each file's
    # C dump is read back by a loader that also keeps what a tree does not
    # carry (the constant pool's entries, which strings are slices of the
    # source, which integers are a negated zero), the writer writes it
    # again, and the two dumps must be equal byte for byte.
    module PrismDiff
      ROOT = File.expand_path("../../..", __dir__)
      UPSTREAM = File.join(ROOT, "tmp/prism-1.9.0")
      # The prism checkout test/prism is extracted from.
      CHECKOUT = File.expand_path("~/dev/prism")
      # test_helper.rb's SYNTAX_VERSIONS.
      SYNTAX_VERSIONS = %w[3.3 3.4 4.0 4.1].freeze
      # ze0's own Ruby, parsed under the latest syntax.
      OWN = %w[rt lib test vendor].freeze

      Case = Struct.new(:name, :source, :options)

      module_function

      # test/prism at prism's v1.9.0 tag, extracted on first use; nil when
      # there is no checkout to extract it from.
      def upstream
        tests = File.join(UPSTREAM, "test/prism")
        return tests if File.directory?(tests)
        return unless File.directory?(CHECKOUT)

        FileUtils.mkdir_p(File.dirname(UPSTREAM))
        system("git -C #{CHECKOUT} archive --prefix=prism-1.9.0/ v1.9.0 test/prism | tar -x -C #{File.dirname(UPSTREAM)}", exception: true)
        tests
      end

      # test_helper.rb's ruby_versions_for: `3.4/x.txt` from 3.4 on,
      # `3.3-3.3/x.txt` for 3.3 alone, a file at the top for every version.
      def versions_for(path)
        parts = path.split("/")
        return SYNTAX_VERSIONS if parts.size == 1

        first, last = parts[0].split("-")
        last ? SYNTAX_VERSIONS[SYNTAX_VERSIONS.index(first)..SYNTAX_VERSIONS.index(last)] : SYNTAX_VERSIONS[SYNTAX_VERSIONS.index(first)..]
      end

      # The cases of each corpus: `fixtures` and `errors` are prism's own,
      # each under every syntax version its directory names; `rt`, `lib`,
      # `test` and `vendor` are ze0's .rb files. `only` is a glob over the
      # case names.
      def cases(corpora, only: nil)
        corpora.flat_map do |corpus|
          case corpus
          when "fixtures", "errors"
            base = File.join(upstream || raise("no prism checkout at #{CHECKOUT}"), corpus)
            Dir.glob("**/*.txt", base: base).sort.flat_map do |path|
              source = File.binread(File.join(base, path))
              # errors_test.rb: the annotation lines go, and so do trailing newlines.
              source = source.lines.grep_v(/^\s*\^/).join.gsub(/\n*\z/, "") if corpus == "errors"
              versions_for(path).map { |version| Case.new("#{corpus}/#{path}@#{version}", source, { version: version }) }
            end
          when *OWN
            Dir.glob("#{corpus}/**/*.rb", base: ROOT).sort.map do |path|
              Case.new(path, File.binread(File.join(ROOT, path)), { filepath: path })
            end
          else
            raise ArgumentError, "unknown corpus #{corpus}"
          end
        end.select { |c| only.nil? || File.fnmatch?(only, c.name, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      end

      # The constant pool of a C dump: each entry's bytes and source offset
      # (nil when owned). Owned entries come in the order their bytes follow
      # the table, which is the order of the C pool's buckets.
      class RecordedPool
        attr_reader :size

        def initialize(input, serialized, base, size)
          @size = size
          @entries = Array.new(size) do |index|
            start, length = serialized.unpack("L2", offset: base + index * 8)
            if start.anybits?(1 << 31)
              [index + 1, serialized.byteslice(start & ~(1 << 31), length), nil, start]
            else
              [index + 1, input.byteslice(start, length), start, -1]
            end
          end
        end

        def each_bucket
          @entries.sort_by { |entry| [entry[3], entry[0]] }.each { |id, bytes, offset, _| yield id, bytes, offset }
        end
      end

      Serialize = Prism.const_get(:Serialize)

      # Serialize::Loader, which also keeps the encoding's name as written,
      # the source offset of each string that is a slice, and the ids of
      # the nodes whose integer is a negated zero.
      class Recorder < Serialize.const_get(:Loader)
        attr_reader :shared, :encoding_name, :negative_zeros

        def initialize(source, serialized)
          super
          @shared = {}.compare_by_identity
          @negative_zeros = []
          @node_ids = []
        end

        # The id of the node being read, for load_integer: it follows the
        # type byte.
        def load_node(constant_pool, encoding, freeze)
          at = io.pos
          io.getbyte
          @node_ids.push(load_varuint)
          io.pos = at
          super
        ensure
          @node_ids.pop
        end

        def load_integer
          at = io.pos
          negative = io.getbyte != 0
          io.pos = at
          super.tap { |value| @negative_zeros << @node_ids.last if negative && value.zero? }
        end

        def load_encoding
          @encoding_name = io.read(load_varuint)
          encoding = Encoding.find(@encoding_name)
          @input = input.force_encoding(encoding).freeze
          encoding
        end

        def load_string(encoding)
          case (type = io.getbyte)
          when 1
            offset = load_varuint
            input.byteslice(offset, load_varuint).force_encoding(encoding).freeze.tap { |string| @shared[string] = offset }
          when 2
            load_embedded_string(encoding)
          else
            raise "Unknown serialized string type: #{type}"
          end
        end

        # Serialize.load_parse's steps: the result, and Dump.parse's other
        # arguments.
        def self.load_parse(input, serialized)
          input = input.dup
          source = Prism::Source.for(input)
          loader = new(source, serialized)
          loader.load_header
          encoding = loader.load_encoding
          start_line = loader.load_varsint
          offsets = loader.load_line_offsets(false)
          source.replace_start_line(start_line)
          source.replace_offsets(offsets)
          comments = loader.load_comments(false)
          magic_comments = loader.load_magic_comments(false)
          data_loc = loader.load_optional_location_object(false)
          errors = loader.load_errors(encoding, false)
          warnings = loader.load_warnings(encoding, false)
          base = loader.load_uint32
          size = loader.load_varuint
          node = loader.load_node(Serialize.const_get(:ConstantPool).new(loader.input, serialized, base, size), encoding, false)
          result = Prism::ParseResult.new(node, comments, magic_comments, data_loc, errors, warnings, source)
          [result, { encoding_name: loader.encoding_name, pool: RecordedPool.new(loader.input, serialized, base, size),
                     shared: loader.shared, negative_zeros: loader.negative_zeros }]
        end
      end

      # The first byte two dumps differ at, with the bytes around it.
      def difference(expected, actual)
        common = [expected.bytesize, actual.bytesize].min
        at = (0...common).find { |i| expected.getbyte(i) != actual.getbyte(i) } || common
        window = ->(bytes) { bytes.byteslice([at - 16, 0].max, 32).unpack1("H*") }
        "sizes #{expected.bytesize}/#{actual.bytesize}, first difference at byte #{at}\n  C:    #{window.(expected)}\n  Ruby: #{window.(actual)}"
      end

      # Each case's C dump written again by the Ruby writer: the cases that
      # differ, as `[name, why]`.
      def writer(cases)
        require File.join(ROOT, "rt/ext/prism/ruby/dump")
        cases.filter_map do |c|
          dump = Prism.dump(c.source, **c.options)
          again = begin
            result, facts = Recorder.load_parse(c.source, dump)
            Prism::Ruby::Dump.parse(result, **facts)
          rescue StandardError => e
            next [c.name, "#{e.class}: #{e.message}\n  #{e.backtrace.first(3).join("\n  ")}"]
          end
          [c.name, difference(dump, again)] unless again == dump
        end
      end
    end
  end
end
