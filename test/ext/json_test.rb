# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"
require "fileutils"
require "open3"
require "tmpdir"

# json, whose own C extension a build for this host links in place of
# zr's port (Library::Ports, `c_first`). Each program gives ruby's
# output, also under ZR_GC_STRESS, where each allocation collects while
# json's parser and generator hold Values, and with ZR_GC_VERIFY. The
# parser's state is an embeddable struct with a thread-safe free
# (RUBY_TYPED_THREAD_SAFE_FREE).
class CExtJsonTest < Minitest::Test
  RUNS = { "" => {}, "_under_stress" => { "ZR_GC_STRESS" => "1" },
           "_verified" => { "ZR_GC_STRESS" => "1", "ZR_GC_VERIFY" => "1" } }.freeze

  def self.same_as_ruby(name, program)
    RUNS.each { |suffix, env| define_method(:"test_#{name}#{suffix}") { assert_same_as_ruby(program, env) } }
  end

  def setup
    skip Zr::Test::CExt::UNSUPPORTED unless Zr::Test::CExt.supported?
    @version = Zr::Library::Ports::ALL.fetch("json").version
    skip "json #{@version} is not installed in this ruby" unless Zr::Test::CExt.installed("json") == @version
  end

  def assert_same_as_ruby(program, env)
    ruby, (zr,) = Zr::Test::CExt.gem_outputs("json", @version, program, [env])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr's output differs from ruby's under #{env}\nzr stderr:\n#{zr.stderr}"
  end

  same_as_ruby "documents_parse_and_generate_as_ruby_s", <<~RUBY
    require "json"
    doc = { "name" => "caf\\u00e9", "list" => [1, 2.5, -3e300, nil, true, false], "nested" => { "a" => [{ "b" => "c" }] * 20 } }
    text = JSON.generate(doc)
    p text.bytesize, JSON.parse(text) == doc, JSON.parse(text, symbolize_names: true).keys
    puts JSON.pretty_generate(doc["nested"]["a"].first(2))
    p JSON.parse("[1e2, -0.0, 12345678901234567890]"), JSON.parse('"\\\\u00e9\\\\n"')
    p JSON.dump([:sym, 1..2]), JSON.parse("{}", object_class: Hash).class
    p JSON.generate("bad \\xff".b) rescue p $!.class
  RUBY

  same_as_ruby "parse_errors_name_the_line_and_the_column", <<~RUBY
    require "json"
    ['{"a": }', "[1, 2", '{"a" 1}', "nul", "[" * 101 + "]" * 101].each do |text|
      JSON.parse(text)
    rescue JSON::ParserError, JSON::NestingError => e
      p [e.class, e.message[0, 80]]
    end
    p JSON.parse("[" * 101 + "]" * 101, max_nesting: false).flatten
  RUBY

  # json 2.19, below the versions whose C the port implements: a build
  # compiles its Ruby, links its own C with --native-ext, and without it
  # raises LoadError at the require of its C part, never the port's C.
  OLD = "2.19.1"
  OLD_HOME = File.expand_path("../../tmp/gem-homes/json-#{OLD}", __dir__)

  def old_json_home
    unless File.directory?(File.join(OLD_HOME, "gems", "json-#{OLD}"))
      _, status = Open3.capture2e(RbConfig.ruby, "-S", "gem", "install", "json", "-v", OLD, "--install-dir", OLD_HOME, "--no-document")
      skip "json #{OLD} could not be installed into #{OLD_HOME}" unless status.success?
    end
    OLD_HOME
  end

  def test_a_json_below_the_port_s_versions_links_its_own_c
    program = %(gem "json", "#{OLD}"\nrequire "json"\np JSON::VERSION, JSON.parse('[1, {"a": "\\\\u00e9"}]'), JSON.generate([nil, 2.5])\n)
    # The child ruby of these tests has json 3 active before the first
    # line, so the answer is written here: json 2.19's, as ruby gives it.
    _, (zr,) = Zr::Test::CExt.gem_outputs("json", OLD, program, [{}], home: old_json_home)
    assert_equal [%(#{OLD.inspect}\n[1, {"a" => "é"}]\n"[null,2.5]"\n).b, 0], [zr.stdout.b, zr.status], zr.stderr
  end

  def test_a_json_below_the_port_s_versions_has_no_c_without_native_ext
    dir = Dir.mktmpdir("zr-json-old-")
    path = File.join(dir, "old.rb")
    File.write(path, %(gem "json", "#{OLD}"\nbegin\n  require "json"\nrescue LoadError => e\n  puts e.class\nend\n))
    env = Zr::Test::CExt::UNBUNDLED.merge("GEM_PATH" => [old_json_home, *Gem.path].join(File::PATH_SEPARATOR))
    built = Zr::Test::CExt.run(env, File.join(Zr::Test::CExt::ROOT, "bin", "zr"), "build", path, "-o", "#{path}.bin")
    assert_equal 0, built.status, built.stderr
    assert_includes built.stderr, "link the gem's own C with --native-ext json=#{OLD}"
    assert_equal "LoadError\n", Zr::Test::CExt.run(env, "#{path}.bin").stdout
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  same_as_ruby "a_coder_and_a_state_keep_their_options", <<~RUBY
    require "json"
    coder = JSON::Coder.new { |obj| obj.to_s }
    p coder.dump([Object.new.then { "obj" }, :s, 1r])
    state = JSON::State.new(indent: "  ", space: " ", object_nl: "\\n", array_nl: "\\n")
    puts state.generate({ "k" => [1, 2] })
    p state.indent, state.depth, JSON::State.new(max_nesting: 2).generate([[1]])
    many = Array.new(2000) { |i| { "i" => i, "s" => "x" * (i % 17) } }
    p JSON.parse(JSON.generate(many)).sum { _1["i"] }
  RUBY
end
