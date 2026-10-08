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
    "bson" => <<~'RUBY',
      require "bson"
      doc = { "a" => 1, "b" => [1, 2.5, "x"], "c" => { "d" => nil, "e" => true }, "big" => 2**40 }
      bytes = doc.to_bson.to_s
      p bytes.bytesize, bytes.unpack1("H*")[0, 40]
      p Hash.from_bson(BSON::ByteBuffer.new(bytes))
    RUBY
    "cgi" => <<~'RUBY',
      require "cgi/escape"
      p CGI.escapeHTML(%(<a href="x">&'</a>)), CGI.unescapeHTML("&lt;b&gt; &amp;amp; &#39;&#x41;&#65; &bogus;")
      p CGI.escape("a b&c/é~"), CGI.unescape("a+b%26c%2F%C3%A9"), CGI.escapeURIComponent("a b+c"), CGI.unescapeURIComponent("a+b%20c")
      p CGI.escapeHTML("plain").frozen?, CGI.escapeHTML("é<").encoding
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
    "hiredis" => <<~'RUBY',
      require "hiredis/ext/reader"
      reader = Hiredis::Ext::Reader.new
      reader.feed("*3\r\n$3\r\nfoo\r\n:42\r\n*2\r\n+OK\r\n$-1\r\n")
      p reader.gets, reader.gets
      reader.feed("-ERR bad thing\r\n$5\r\nhel")
      error = reader.gets
      p error.class, error.message, reader.gets
      reader.feed("lo\r\n")
      p reader.gets
      begin
        reader.feed("?\r\n")
        reader.gets
      rescue => e
        p e.class
      end
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
    "yajl-ruby" => <<~'RUBY',
      require "yajl"
      p Yajl::Parser.parse('{"a":[1,2.5,"x",null,true],"b":{"c":"é"}}')
      puts Yajl::Encoder.encode({ "a" => [1, nil, "q\"uote"], "b" => 2.5 })
      p Yajl::Parser.parse('{"k":1}', symbolize_keys: true)
      begin
        Yajl::Parser.parse("{bad")
      rescue Yajl::ParseError => e
        p e.class
      end
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
  # bson and rbs load a large Ruby half: under ZR_GC_STRESS, which
  # collects at each allocation, each program takes minutes, past a
  # test's bound.
  UNSTRESSED = %w[bson rbs].freeze
  # unf_ext's C++ throws exceptions, which only dyld's unwinder handles:
  # its bundle loads with dlopen.
  BUILD_ENVS = { "unf_ext" => { "ZR_EXT" => "dynamic" } }.freeze

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  PROGRAMS.each do |name, program|
    RUNS.each do |suffix, env|
      next if UNSTRESSED.include?(name) && env.key?("ZR_GC_STRESS")

      define_method(:"test_#{name.tr(".-", "__")}_runs_as_in_ruby#{suffix}") do
        version = Reference::NATIVE.fetch(name)
        home = Reference.native_home(name, version)
        skip "#{name} #{version} is not installed (bin/setup)" unless File.directory?(home)

        ruby, (zr,) = Zr::Test::CExt.gem_outputs(name, version, program, [env], build_env: BUILD_ENVS.fetch(name, {}), home: home)
        assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
        assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
      end
    end
  end
end
