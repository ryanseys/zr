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
    "fast_blank" => <<~'RUBY',
      require "fast_blank"
      p ["", " ", "\t\n\r", "a", " a ", " ", "　", " x"].map { |s| [s.blank?, s.blank_as?] }
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
  # bson loads a large Ruby half: under ZR_GC_STRESS, which collects at
  # each allocation, its program takes four minutes, past a test's bound.
  UNSTRESSED = %w[bson].freeze

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

        ruby, (zr,) = Zr::Test::CExt.gem_outputs(name, version, program, [env], home: home)
        assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
        assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr stderr:\n#{zr.stderr}"
      end
    end
  end
end
