# frozen_string_literal: true

require "fileutils"
require "prism"
require_relative "child"

module Zr
  module Harness
    # Compares the pure-Ruby prism (runtime/ext/prism/ruby) with ruby's
    # own C prism, file by file. The C prism is the reference.
    #
    # `writer` tests Prism::Ruby::Dump without the Ruby parser. A loader
    # reads each file's C dump back, and also keeps the data that a tree
    # does not contain: the constant pool entries, which strings are
    # slices of the source, and which integers are a negated zero. The
    # writer writes the dump again, and the two dumps must be equal byte
    # for byte.
    module PrismDiff
      ROOT = File.expand_path("../../..", __dir__)
      UPSTREAM = File.join(ROOT, "tmp/prism-1.9.0")
      # The prism checkout that test/prism is extracted from.
      CHECKOUT = File.expand_path("~/dev/prism")
      # test_helper.rb's SYNTAX_VERSIONS.
      SYNTAX_VERSIONS = %w[3.3 3.4 4.0 4.1].freeze
      # zr's own Ruby, parsed under the latest syntax.
      OWN = %w[runtime lib test vendor].freeze

      Case = Struct.new(:name, :source, :options)

      module_function

      # The parts of prism's v1.9.0 tag that the tests read: prism's tests
      # and the snapshots that they compare with. They are extracted on
      # first use.
      UPSTREAM_PARTS = %w[test/prism snapshots].freeze

      # The path of test/prism at prism's v1.9.0 tag, extracted on first
      # use. nil when there is no checkout to extract it from.
      def upstream
        tests = File.join(UPSTREAM, "test/prism")
        missing = UPSTREAM_PARTS.reject { |part| File.directory?(File.join(UPSTREAM, part)) }
        return tests if missing.empty?
        return unless File.directory?(CHECKOUT)

        FileUtils.mkdir_p(File.dirname(UPSTREAM))
        system("git -C #{CHECKOUT} archive --prefix=prism-1.9.0/ v1.9.0 #{missing.join(" ")} | tar -x -C #{File.dirname(UPSTREAM)}", exception: true)
        tests
      end

      # The directory whose prism/prism.rb is used in place of the C extension.
      RUBY_BACKEND = File.join(ROOT, "lib/zr/prism_shim")

      # The counts of one test file, as test-unit reports them.
      TestRun = Struct.new(:file, :tests, :assertions, :failures, :errors, :pendings, :omissions, :output) do
        def passed? = !tests.nil? && failures.zero? && errors.zero?
        def counts = to_a[1..6]
      end

      # Runs prism's own test files (test/prism/**/*_test.rb at v1.9.0) on
      # the C extension or the Ruby port (`backend` :c or :ruby). Each file
      # runs in its own ruby, with a time and memory limit, and at most
      # `jobs` run at a time. Returns one TestRun for each file.
      def upstream_tests(backend, only: nil, jobs: 3, seconds: 600, megabytes: 3000)
        base = File.dirname(upstream || raise("no prism checkout at #{CHECKOUT}"))
        check = "exit(Prism.method(:parse).source_location.nil? ? 1 : 0)"
        raise "the Ruby backend does not load from #{RUBY_BACKEND}" if backend == :ruby && !system(RbConfig.ruby, "-I", RUBY_BACKEND, "-rprism", "-e", check)
        files = Dir.glob("prism/**/*_test.rb", base: base).sort
        files = files.select { |file| File.fnmatch?(only, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) } if only
        queue = Queue.new
        files.each { |file| queue << file }
        queue.close
        runs = Array.new(jobs) do
          Thread.new do
            done = []
            while (file = queue.pop)
              done << upstream_test(base, file, backend, seconds, megabytes)
            end
            done
          end
        end.flat_map(&:value)
        runs.sort_by(&:file)
      end

      def upstream_test(base, file, backend, seconds, megabytes)
        includes = backend == :ruby ? ["-I", RUBY_BACKEND] : []
        answer, = Child.run([RbConfig.ruby, *includes, "-I", base, File.join(base, file)], cwd: File.dirname(base), seconds: seconds, megabytes: megabytes)
        output = "#{answer.stdout}#{answer.stderr}"
        output += "\n(stopped: #{answer.code})" if answer.code.is_a?(Symbol)
        counts = output[/^(\d+) tests, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) pendings, (\d+) omissions/]
        TestRun.new(file, *(counts ? Regexp.last_match.captures.map(&:to_i) : Array.new(6)), output)
      end

      # The same as test_helper.rb's ruby_versions_for: `3.4/x.txt` is for
      # 3.4 and later, `3.3-3.3/x.txt` is for 3.3 only, and a file at the
      # top is for all versions.
      def versions_for(path)
        parts = path.split("/")
        return SYNTAX_VERSIONS if parts.size == 1

        first, last = parts[0].split("-")
        last ? SYNTAX_VERSIONS[SYNTAX_VERSIONS.index(first)..SYNTAX_VERSIONS.index(last)] : SYNTAX_VERSIONS[SYNTAX_VERSIONS.index(first)..]
      end

      # The cases of each corpus. `fixtures` and `errors` are prism's own,
      # with one case for each syntax version that the directory gives.
      # `runtime`, `lib`, `test` and `vendor` are zr's .rb files. `only` is
      # a glob that selects case names.
      def cases(corpora, only: nil)
        corpora.flat_map do |corpus|
          case corpus
          when "fixtures", "errors"
            base = File.join(upstream || raise("no prism checkout at #{CHECKOUT}"), corpus)
            Dir.glob("**/*.txt", base: base).sort.flat_map do |path|
              source = File.binread(File.join(base, path))
              # As in errors_test.rb: remove the annotation lines and trailing newlines.
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

      # The constant pool of a C dump: the bytes and source offset of each
      # entry (the offset is nil for an owned entry). Owned entries are in
      # the order of their bytes after the table, which is the order of the
      # C pool's hash buckets.
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

      # A Serialize::Loader that also keeps the encoding name as written,
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

        # Keeps the id of the node that is being read, for load_integer.
        # The id follows the type byte.
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

        # The steps of Serialize.load_parse. Returns the result, and the
        # other arguments of Dump.parse.
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

      # The first byte where two dumps differ, with the bytes around it.
      def difference(expected, actual)
        common = [expected.bytesize, actual.bytesize].min
        at = (0...common).find { |i| expected.getbyte(i) != actual.getbyte(i) } || common
        window = ->(bytes) { bytes.byteslice([at - 16, 0].max, 32).unpack1("H*") }
        "sizes #{expected.bytesize}/#{actual.bytesize}, first difference at byte #{at}\n  C:    #{window.(expected)}\n  Ruby: #{window.(actual)}"
      end

      # Writes the C dump of each case again with the Ruby writer. Returns
      # the cases that differ, as `[name, why]`.
      def writer(cases)
        require File.join(ROOT, "runtime/ext/prism/ruby/dump")
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

      # Compares the Ruby parser with the C parser: Prism::Ruby.dump must
      # write the same bytes as Prism.dump for each case. Returns the cases
      # that differ, as `[name, why]`.
      def dump(cases)
        require File.join(ROOT, "runtime/ext/prism/ruby")
        cases.filter_map do |c|
          expected = Prism.dump(c.source, **c.options)
          actual = begin
            Prism::Ruby.dump(c.source, **c.options)
          rescue StandardError, SystemStackError => e
            next [c.name, "#{e.class}: #{e.message}\n  #{e.backtrace.first(4).join("\n  ")}"]
          end
          [c.name, difference(expected, actual)] unless actual == expected
        end
      end

      # The first place where two object graphs differ, as `path: why`, or
      # nil. Objects compare by class, frozen state and instance variables.
      # Strings compare by bytes and encoding, and Floats by their bits. An
      # object that occurs again in one graph must also occur again at the
      # same place in the other, because all nodes share the result's Source.
      class Graph
        def self.difference(expected, actual) = new.difference(expected, actual, "result")

        def initialize
          @seen = {}.compare_by_identity
        end

        def difference(expected, actual, path)
          return "#{path}: C #{expected.class}, Ruby #{actual.class}" unless expected.class == actual.class
          return "#{path}: C frozen #{expected.frozen?}, Ruby frozen #{actual.frozen?}" unless expected.frozen? == actual.frozen?

          case expected
          when String, Symbol
            "#{path}: C #{expected.inspect} (#{expected.encoding}), Ruby #{actual.inspect} (#{actual.encoding})" unless expected.to_s.b == actual.to_s.b && expected.encoding == actual.encoding
          when Float
            "#{path}: C #{expected}, Ruby #{actual}" unless [expected].pack("G") == [actual].pack("G")
          when Integer, NilClass, TrueClass, FalseClass, Module
            "#{path}: C #{expected.inspect}, Ruby #{actual.inspect}" unless expected.equal?(actual) || expected == actual
          when Array
            return "#{path}: C #{expected.size} elements, Ruby #{actual.size}" unless expected.size == actual.size

            expected.each_with_index do |value, index|
              why = difference(value, actual[index], "#{path}[#{index}]")
              return why if why
            end
            nil
          else
            if (seen = @seen[expected])
              return seen.equal?(actual) ? nil : "#{path}: C meets an object again, Ruby a different one"
            end

            @seen[expected] = actual
            names = expected.instance_variables
            return "#{path}: C #{names}, Ruby #{actual.instance_variables}" unless names == actual.instance_variables

            names.each do |name|
              why = difference(expected.instance_variable_get(name), actual.instance_variable_get(name), "#{path}.#{name.to_s.delete_prefix("@")}")
              return why if why
            end
            nil
          end
        end
      end

      # Compares an entry point with the C extension's, object by object
      # (Graph). Each case goes through `Prism.<method>` and
      # `Prism::Ruby.<method>` with its options.
      def api(cases, method, **extra)
        require File.join(ROOT, "runtime/ext/prism/ruby")
        cases.filter_map do |c|
          why = call_difference(Prism, Prism::Ruby) { |receiver| receiver.public_send(method, c.source, **c.options, **extra) }
          [c.name, why] if why
        end
      end

      # How the block's result with the C extension's receiver (Prism,
      # Prism::Pack, Prism::StringQuery) differs from its result with the
      # Ruby port's receiver, or nil. A raised error is also a result, and
      # compares by class and message.
      def call_difference(c, ruby)
        expected = answer { yield c }
        actual = answer { yield ruby }
        why = Graph.difference(expected.first(3), actual.first(3))
        return why unless why && actual.first == :raised && expected.first != :raised

        "#{why}\n  #{actual[1]}: #{actual[2]}\n  #{actual[3].join("\n  ")}"
      end

      # `[result]` of the block, or `[:raised, class, message, backtrace]`.
      def answer
        [yield]
      rescue StandardError, SystemStackError => e
        [:raised, e.class, e.message, e.backtrace.first(4)]
      end

      # Bytes the fuzzer inserts: the characters that open, close or join
      # constructs.
      FUZZ_BYTES = "()[]{}|&*,.:;=<>?!@$#%'\"`\\/\n -+^~_1aZ".b

      # Makes `count` broken variants of each case, with the random seed
      # `seed`. A variant is cut at a random offset, has a random range
      # removed, or has a random byte added. Returns cases named `name~n`.
      def fuzz(cases, count, seed)
        random = Random.new(seed)
        cases.flat_map do |c|
          source = c.source.b
          Array.new(count) do |index|
            at = source.empty? ? 0 : random.rand(source.bytesize)
            variant =
              case index % 3
              when 0 then source.byteslice(0, at)
              when 1 then source.byteslice(0, at) + source.byteslice([at + random.rand(1..8), source.bytesize].min..)
              else source.byteslice(0, at) + FUZZ_BYTES.byteslice(random.rand(FUZZ_BYTES.bytesize), 1) + source.byteslice(at..)
              end
            Case.new("#{c.name}~#{index}", variant, c.options)
          end
        end
      end

      # Compares the lexer alone with Prism.lex: the type and byte range of
      # each token, and with `states` its lex state. Without the parser, the
      # lexer differs where the parser changes the lex state. Thus this
      # compares tokens up to the first difference, and reports it. A case
      # that needs an unimplemented lex mode counts as `unsupported`.
      # Returns `[failures, unsupported]`, each failure as `[name, why]`.
      def lex(cases, states: false)
        require File.join(ROOT, "runtime/ext/prism/ruby")
        unsupported = 0
        failures = cases.filter_map do |c|
          expected = Prism.lex(c.source, **c.options).value.map do |token, state|
            [token.type, token.location.start_offset, token.location.length, (state if states)]
          end
          actual = begin
            Prism::Ruby.lex_tokens(c.source, **c.options).map { |type, start, length, state| [type, start, length, (state if states)] }
          rescue NotImplementedError
            unsupported += 1
            next
          rescue StandardError => e
            next [c.name, "#{e.class}: #{e.message}\n  #{e.backtrace.first(3).join("\n  ")}"]
          end
          next if actual == expected

          at = (0...[expected.size, actual.size].max).find { |i| expected[i] != actual[i] }
          line = c.source.byteslice(0, (expected[at] || actual[at] || [nil, c.source.bytesize])[1]).count("\n") + 1
          [c.name, "token #{at} (line #{line}): C #{expected[at].inspect}, Ruby #{actual[at].inspect}"]
        end
        [failures, unsupported]
      end
    end
  end
end
