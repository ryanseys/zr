# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"
require_relative "../support/harness/reference"

# Gems with a C extension that the most downloaded gems need
# (`zr-dev ext rank`), each in a zr binary that runs the C that the
# reference ruby compiled when it installed the gem
# (Zr::Harness::Reference::NATIVE). Each program gives ruby's output, also
# under ZR_GC_STRESS.
class CExtTopGemsTest < Minitest::Test
  Reference = Zr::Harness::Reference

  PROGRAMS = {
    "bcrypt" => <<~'RUBY',
      require "bcrypt"
      salt = "$2a$04$abcdefghijklmnopqrstuu"
      hash = BCrypt::Engine.hash_secret("secret", salt)
      p hash, BCrypt::Engine.valid_salt?(salt), BCrypt::Engine.valid_salt?("nope")
      password = BCrypt::Password.new(hash)
      p password == "secret", password == "wrong", password.cost, password.salt
    RUBY
    "bindex" => <<~'RUBY',
      require "bindex"

      def boom(n)
        secret = n * 3
        raise ArgumentError, "boom #{secret}"
      end

      def middle(m)
        label = "middle"
        boom(m + 1)
      end

      begin
        middle(6)
      rescue ArgumentError => e
        bindings = e.bindings
        p e.message, bindings.size >= 3
        p bindings[0].local_variables.sort, bindings[0].local_variable_get(:secret)
        p bindings[1].local_variable_get(:label), bindings[1].local_variable_get(:m)
        p bindings[0].eval("n + secret")
      end
      p RuntimeError.new("unraised").bindings
    RUBY
"binding_ninja" => <<~'RUBY',
  require "binding_ninja"
  class Greeter
    extend BindingNinja

    def greet(caller_binding, name)
      [caller_binding.class, caller_binding.receiver.class, caller_binding.local_variable_get(:greeting), name]
    end
    auto_inject_binding :greet

    def maybe(caller_binding, name) = [caller_binding.nil?, name]
    auto_inject_binding :maybe, if: :inject?

    def inject? = false
  end
  greeting = "hello"
  p Greeter.new.greet("ruby"), Greeter.new.maybe("zr")
RUBY
    "bson" => <<~'RUBY',
      require "bson"
      doc = { "a" => 1, "b" => [1, 2.5, "x"], "c" => { "d" => nil, "e" => true }, "big" => 2**40 }
      bytes = doc.to_bson.to_s
      p bytes.bytesize, bytes.unpack1("H*")[0, 40]
      p Hash.from_bson(BSON::ByteBuffer.new(bytes))
    RUBY
    "byebug" => <<~'RUBY',
      require "byebug"
      require "byebug/core"
      require "tmpdir"

      def add(a, b)
        sum = a + b
        sum * 2
      end

      def run
        total = 1
        byebug
        total = add(total, 2)
        total + 1
      end

      script = File.join(Dir.mktmpdir, "commands")
      File.write(script, <<~COMMANDS)
        p total
        step
        p [a, b]
        next
        p sum
        p [Byebug.current_context.frame_method, Byebug.current_context.frame_line, Byebug.current_context.stack_size > 2]
        continue
      COMMANDS
      Byebug.init_file = File.join(File.dirname(script), "none")
      Byebug::Setting[:histfile] = File.join(File.dirname(script), "history")
      Byebug::Setting[:autolist] = false
      Byebug::Context.interface = Byebug::ScriptInterface.new(script, true)
      p run, Byebug.started?
    RUBY
    "cgi" => <<~'RUBY',
      require "cgi/escape"
      p CGI.escapeHTML(%(<a href="x">&'</a>)), CGI.unescapeHTML("&lt;b&gt; &amp;amp; &#39;&#x41;&#65; &bogus;")
      p CGI.escape("a b&c/é~"), CGI.unescape("a+b%26c%2F%C3%A9"), CGI.escapeURIComponent("a b+c"), CGI.unescapeURIComponent("a+b%20c")
      p CGI.escapeHTML("plain").frozen?, CGI.escapeHTML("é<").encoding
    RUBY
    "debug_inspector" => <<~'RUBY',
      require "debug_inspector"

      class Walker
        def inner(x)
          y = x * 2
          DebugInspector.open do |dc|
            locations = dc.backtrace_locations
            (0...4).map do |i|
              binding = dc.frame_binding(i)
              [locations[i].label, locations[i].lineno, dc.frame_self(i).class, dc.frame_class(i),
               binding && binding.local_variables.sort, binding && binding.local_variable_defined?(:y) && binding.local_variable_get(:y)]
            end
          end
        end

        def outer = inner(21)
      end

      Walker.new.outer.each { |row| p row }
      p DebugInspector.open { |dc| dc.frame_binding(1).receiver.class }
    RUBY
    "ed25519" => <<~'RUBY',
      require "ed25519"
      key = Ed25519::SigningKey.new("\x01".b * 32)
      signature = key.sign("message")
      p signature.unpack1("H*"), key.verify_key.to_bytes.unpack1("H*")
      p key.verify_key.verify(signature, "message")
      begin
        key.verify_key.verify(signature, "other")
      rescue Ed25519::VerifyError => e
        p e.class
      end
    RUBY
    "erb" => <<~'RUBY',
      require "erb/escape"
      p ERB::Escape.html_escape(%(<a href="x">&'</a>)), ERB::Escape.html_escape("plain"), ERB::Escape.html_escape(42)
      s = "same"
      p ERB::Escape.html_escape(s).equal?(s)
    RUBY
    "escape_utils" => <<~'RUBY',
      require "escape_utils"
      p EscapeUtils.escape_html(%(<a href="x">&'</a>)), EscapeUtils.escape_html_once("&amp; <")
      p EscapeUtils.escape_javascript("line\n'quote' </script>"), EscapeUtils.unescape_javascript("a\\nb")
      p EscapeUtils.escape_xml("<a>&\"'"), EscapeUtils.escape_uri("a b/c?d"), EscapeUtils.escape_url("a b/c?d"), EscapeUtils.unescape_url("a+b%2Fc")
    RUBY
    "fast_blank" => <<~'RUBY',
      require "fast_blank"
      p ["", " ", "\t\n\r", "a", " a ", " ", "　", " x"].map { |s| [s.blank?, s.blank_as?] }
    RUBY
    "google-protobuf" => <<~'RUBY',
      require "google/protobuf/timestamp_pb"
      require "google/protobuf/duration_pb"
      require "google/protobuf/struct_pb"
      stamp = Google::Protobuf::Timestamp.new(seconds: 1_700_000_000, nanos: 5)
      bytes = Google::Protobuf::Timestamp.encode(stamp)
      p bytes.unpack1("H*"), Google::Protobuf::Timestamp.decode(bytes).seconds, stamp.to_h
      p Google::Protobuf::Timestamp.encode_json(stamp), Google::Protobuf::Duration.decode_json('"1.5s"').to_h
      s = Google::Protobuf::Struct.decode_json('{"a":[1,"x",true,null],"b":{"c":2.5}}')
      p s.fields["b"].struct_value.fields["c"].number_value, s.fields.keys.sort, s == Google::Protobuf::Struct.decode(Google::Protobuf::Struct.encode(s))
      begin
        Google::Protobuf::Timestamp.new(bogus: 1)
      rescue ArgumentError => e
        p e.class
      end
    RUBY
"gvltools" => <<~'RUBY',
  require "gvltools"
  metrics = [GVLTools::GlobalTimer, GVLTools::LocalTimer, GVLTools::WaitingThreads]
  metrics.each(&:enable)
  p metrics.map(&:enabled?)
  threads = 3.times.map { Thread.new { 2000.times { Thread.pass } } }
  threads.each(&:join)
  p GVLTools::GlobalTimer.monotonic_time.positive?, GVLTools::WaitingThreads.count
  metrics.each(&:disable)
  GVLTools::GlobalTimer.reset
  p metrics.map(&:enabled?), GVLTools::GlobalTimer.monotonic_time
RUBY
    "http_parser.rb" => <<~'RUBY',
      require "http_parser"
      parser = Http::Parser.new
      bodies = []
      parser.on_headers_complete = proc { p [parser.http_method, parser.request_url, parser.headers] }
      parser.on_body = proc { |chunk| bodies << chunk }
      parser.on_message_complete = proc { p [:done, bodies.join] }
      parser << "POST /items?id=7 HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\n\r\nhello"
      begin
        Http::Parser.new << "NOT HTTP\r\n\r\n"
      rescue Http::Parser::Error => e
        p e.class
      end
    RUBY
    "jaro_winkler" => <<~'RUBY',
      require "jaro_winkler"
      p JaroWinkler.distance("MARTHA", "MARHTA"), JaroWinkler.jaro_distance("MARTHA", "MARHTA")
      p JaroWinkler.distance("abc", "ABC", ignore_case: true), JaroWinkler.distance("", ""), JaroWinkler.distance("café", "cafe")
    RUBY
    "murmurhash3" => <<~'RUBY',
      require "murmurhash3"
      p MurmurHash3::V32.str_hash("hello"), MurmurHash3::V32.str_hash("hello", 7), MurmurHash3::V32.int32_hash(42)
      p MurmurHash3::V128.str_hash("hello"), MurmurHash3::V128.int64_hash(2**40), MurmurHash3::V32.str_digest("abc").unpack1("H*")
    RUBY
    "nio4r" => <<~'RUBY',
      require "nio"
      selector = NIO::Selector.new
      r, w = IO.pipe
      monitor = selector.register(r, :r)
      p selector.select(0.01), selector.registered?(r)
      w << "x"
      ready = selector.select(1)
      p ready.map { |m| [m.io == r, m.readable?, m.writable?, m.interests] }
      monitor.interests = :rw
      p monitor.interests
      p selector.deregister(r).closed?, selector.empty?
      buffer = NIO::ByteBuffer.new(16)
      buffer << "hello"
      buffer.flip
      p buffer.get(3), buffer.position, buffer.remaining, buffer.limit
      w2 = IO.pipe
      buffer.clear
      buffer << "data!"
      buffer.flip
      p buffer.write_to(w2[1]), w2[0].read_nonblock(10)
      selector.close
      p selector.closed?
    RUBY
    "oj" => <<~'RUBY',
      require "oj"
      p Oj.dump({ "a" => [1, 2.5, nil, true], "b" => { "c" => "é" } }, mode: :compat)
      p Oj.load('{"x":[1,2,{"y":null}],"z":1.5e3}'), Oj.load("[1,2]", symbol_keys: true)
      p Oj.load('{"k":"v"}', mode: :strict, symbol_keys: true)
      p Oj.dump(nil), Oj.dump("q\"uote\n"), Oj.generate({ "a" => 1 })
      begin
        Oj.load("{bad")
      rescue => e
        p e.class
      end
    RUBY
    "puma" => <<~'RUBY',
      require "puma/puma_http11"
      parser = Puma::HttpParser.new
      env = {}
      read = parser.execute(env, "GET /a/b?c=d HTTP/1.1\r\nHost: x.org\r\nX-Thing: yes\r\n\r\n", 0)
      p read, parser.finished?, parser.error?, env.sort
      begin
        Puma::HttpParser.new.execute({}, "BAD\r\n\r\n", 0)
      rescue Puma::HttpParserError => e
        p e.class
      end
    RUBY
    "rbs" => <<~'RUBY',
      require "rbs"
      _, _, decls = RBS::Parser.parse_signature(<<~RBS)
        class Foo[T] < Bar
          attr_reader name: String
          def bar: (Integer, ?String) -> Array[T]
                 | () -> void
        end
        module M
          CONST: Integer
        end
      RBS
      decls.each { |d| p [d.class, d.name.to_s, d.members.map { |m| m.class.name }] }
      p RBS::Parser.parse_type("Hash[Symbol, Integer?]").to_s, RBS::Parser.parse_method_type("(String) { (Integer) -> void } -> bool").to_s
      begin
        RBS::Parser.parse_signature("class end")
      rescue RBS::ParsingError => e
        p e.class
      end
    RUBY
    "rbtree" => <<~'RUBY',
      require "rbtree"
      tree = RBTree.new
      tree[3] = "c"
      tree[1] = "a"
      tree[2] = "b"
      p tree.to_a, tree.first, tree.last, tree.lower_bound(2), tree.upper_bound(2), tree.bound(1, 2).to_a
      tree.readjust { |a, b| b <=> a }
      p tree.to_a, tree.delete(2), tree.size
      multi = MultiRBTree.new
      multi[1] = :a
      multi[1] = :b
      multi[0] = :z
      p multi.to_a, multi.count, multi.each_pair.map { |k, v| "#{k}#{v}" }
      p tree.select { |k, _| k > 1 }, tree.map { |k, v| v * k }, tree == RBTree[3 => "c", 1 => "a"]
    RUBY
"rbtree3" => <<~'RUBY',
  require "rbtree"
  tree = RBTree[{ "c" => 3, "a" => 1, "b" => 2 }]
  p tree.to_a, tree.first, tree.last, tree.lower_bound("bb"), tree.to_hash
  tree.default = 0
  hash = tree.to_hash
  p hash.class, hash, hash["missing"], RBTree.new.to_hash
RUBY
    "redcarpet" => <<~'RUBY',
      require "redcarpet"
      require "redcarpet/render_strip"
      markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true, fenced_code_blocks: true)
      puts markdown.render("# Hi\n\n*a* **b** http://x.com\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```ruby\np 1\n```\n")
      puts Redcarpet::Render::SmartyPants.render(%("quoted" -- dash ... it's))
      puts Redcarpet::Markdown.new(Redcarpet::Render::StripDown).render("**plain** _text_")
    RUBY
    "rinku" => <<~'RUBY',
      require "rinku"
      puts Rinku.auto_link("see http://example.com, www.x.org and a@b.co", :all, 'class="l"')
      puts Rinku.auto_link("only https://u.rl/x?y=1", :urls) { |url| url.upcase }
    RUBY
    "ruby-prof" => <<~'RUBY',
      require "ruby-prof"

      class Tree
        def initialize(depth) = @kids = depth.zero? ? [] : Array.new(2) { Tree.new(depth - 1) }
        def size = 1 + @kids.sum(&:size)
      end

      def build = Tree.new(4).size

      result = RubyProf::Profile.profile { build }
      methods = result.threads.first.methods
      rows = methods.select { |m| m.klass_name == "Tree" }.map { |m| [m.full_name, m.called] }.sort
      p rows
      p result.threads.size, methods.map(&:full_name).include?("Object#build")

      profile = RubyProf::Profile.new(measure_mode: RubyProf::ALLOCATIONS, track_allocations: true)
      profile.start
      Array.new(10) { "s" * 3 }
      result = profile.stop
      p result.threads.first.methods.any? { |m| m.allocations.any? }
    RUBY
    "stackprof" => <<~'RUBY',
      require "stackprof"

      def churn = 2_000.times.map { |i| "item #{i}" }

      report = StackProf.run(mode: :object, interval: 1, raw: true) { churn }
      p report[:mode], report[:samples] > 0
      names = report[:frames].values.map { |frame| frame[:name] }
      p names.include?("Object#churn")
      p StackProf.running?
    RUBY
    "thrift" => <<~'RUBY',
      require "thrift"
      [Thrift::BinaryProtocolAccelerated, Thrift::CompactProtocol].each do |klass|
        buffer = Thrift::MemoryBufferTransport.new
        proto = klass.new(buffer)
        proto.write_i32(-42)
        proto.write_string("héllo")
        proto.write_double(1.5)
        proto.write_bool(true)
        proto.write_i64(2**40)
        p [klass.name, buffer.available]
        p [proto.read_i32, proto.read_string, proto.read_double, proto.read_bool, proto.read_i64]
      end
    RUBY
    "unf_ext" => <<~'RUBY',
      require "unf_ext"
      n = UNF::Normalizer.new
      p n.normalize("é", :nfd).bytes, n.normalize("é", :nfc), n.normalize("ﬁ", :nfkc), n.normalize("①", :nfkd)
    RUBY
    "zstd-ruby" => <<~'RUBY'
      require "zstd-ruby"
      data = "hello zstd " * 200
      packed = Zstd.compress(data)
      p packed.bytesize < data.bytesize, Zstd.decompress(packed) == data, Zstd.decompress(Zstd.compress(data, level: 19)) == data
      stream = Zstd::StreamingCompress.new
      stream << "part one, "
      stream << "part two"
      p Zstd.decompress(stream.finish)
    RUBY
  }.freeze

  RUNS = { "" => {}, "_under_stress" => { "ZR_GC_STRESS" => "1" } }.freeze
  # bson and rbs load a large Ruby half, and byebug loads 115 files and
  # reline, then compiles each command's expression as it runs
  # (binding.eval): under ZR_GC_STRESS, which collects the whole heap at
  # each allocation, each program takes minutes, past a test's bound.
  UNSTRESSED = %w[bson byebug rbs].freeze
  # unf_ext's C++ throws exceptions, which only dyld's unwinder handles:
  # its bundle loads with dlopen. On Linux zr builds zstd-ruby's C as
  # ruby's install did there: Alpine's fortified headers stop zstd's
  # C unless _FORTIFY_SOURCE is off (tool/install_reference_gems.rb).
  BUILD_ENVS = { "unf_ext" => { "ZR_EXT" => "dynamic" },
                 "zstd-ruby" => Zr::Target::AARCH64_DARWIN.native? ? {} : { "ZR_EXT_CONFIG" => "zstd-ruby=--with-cflags=-U_FORTIFY_SOURCE" } }.freeze

  # The gems whose activation needs another gem of Reference::NATIVE,
  # which has its own home: puma's gemspec depends on nio4r.
  DEPENDS = { "puma" => %w[nio4r] }.freeze

  # The gems whose Ruby requires openssl, which a static Linux binary
  # cannot open (docs/reference/dependencies.md).
  OPENSSL = %w[bcrypt thrift].freeze

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
  end

  PROGRAMS.each do |name, program|
    RUNS.each do |suffix, env|
      next if UNSTRESSED.include?(name) && env.key?("ZR_GC_STRESS")

      define_method(:"test_#{name.tr(".-", "__")}_runs_as_in_ruby#{suffix}") do
        version = Reference::NATIVE.fetch(name)
        home = Reference.native_home(name, version)
        skip "#{name} #{version} is not installed (bin/setup)" unless File.directory?(home)
        if OPENSSL.include?(name) && !Zr::Target::AARCH64_DARWIN.native?
          skip "#{name} requires openssl, which a static binary cannot open"
        end

        homes = [home, *DEPENDS.fetch(name, []).map { |dep| Reference.native_home(dep, Reference::NATIVE.fetch(dep)) }]
        ruby, (zr,) = Zr::Test::CExt.gem_outputs(name, version, program, [env], build_env: BUILD_ENVS.fetch(name, {}), home: homes)
        # A ruby of a development ABI loads only an extension that exports
        # ruby_abi_version, which rinku's -fvisibility=hidden hides.
        skip "ruby cannot load #{name}: its bundle hides ruby_abi_version" if ruby.stderr.include?("symbol not found - ruby_abi_version")
        assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
        assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
      end
    end
  end
end
