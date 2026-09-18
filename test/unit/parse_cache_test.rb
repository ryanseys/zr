# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require_relative "../../lib/ze0/prism"
require_relative "../../lib/ze0/parse_cache"
require_relative "../support/harness/prism_diff"

# The host parses with the Ruby port, and keeps each parse in the cache
# (lib/ze0/parse_cache.rb). The cache fails closed: every input of a parse
# is in the key, and a file that does not read back is a miss.
class ParseCacheTest < Minitest::Test
  ParseCache = Ze0::ParseCache

  # Asked in a child, and not of this process. A process that loaded
  # ruby's own C prism first keeps it (`lib/ze0/prism.rb` says so), and
  # this tier holds the harness that loads the C on purpose -- so what
  # this process ended up with says nothing about what the compiler uses.
  # A fresh ruby that requires `ze0/prism` is the compiler's own case.
  def test_the_host_parses_with_the_ruby_port_and_the_vendored_ruby_half
    parse, gem, node, native = compiler_process.lines(chomp: true)

    assert_equal File.join(ROOT, "rt/ext/prism/prism.rb"), parse
    assert_equal File.join(ROOT, "vendor/ext/prism/lib/prism.rb"), gem
    assert_equal "true", node
    assert_equal "[]", native
  end

  def test_each_input_of_a_parse_changes_the_key
    base = ParseCache.key("x = 1\n", filepath: "a.rb", line: 1)
    variants = [
      ParseCache.key("x = 2\n", filepath: "a.rb", line: 1),
      ParseCache.key("x = 1\n".b + "\xFF".b, filepath: "a.rb", line: 1),
      ParseCache.key("x = 1\n", filepath: "b.rb", line: 1),
      ParseCache.key("x = 1\n", filepath: "a.rb", line: 2),
      ParseCache.key("x = 1\n", filepath: "a.rb", line: 1, scopes: [[:x]]),
      ParseCache.key("x = 1\n", filepath: "a.rb", line: 1, scopes: [[:y]])
    ]
    assert_equal variants.size + 1, [base, *variants].uniq.size
  end

  def test_the_parser_digest_covers_the_port_the_backend_and_the_gems_ruby_half
    files = ParseCache.parser_files
    [
      "rt/ext/prism/ruby/parser/core.rb", "rt/ext/prism/ruby/lexer.rb", "rt/ext/prism/ruby/ast.rb", "rt/ext/prism/prism.rb",
      "lib/ze0/prism_backend/prism/prism.rb", "lib/ze0/prism.rb", "lib/ze0/parse_cache.rb"
    ].each { |path| assert_includes files, File.join(ROOT, path) }
    gem = $LOAD_PATH.resolve_feature_path("prism").last
    assert_includes files, gem
    assert_includes files, File.join(File.dirname(gem), "prism/node.rb")
  end

  # The second ask for a source this process has parsed answers with the
  # tree it already holds, and reads no file. A worker of the spec tier
  # runs a hundred examples that each require "set", and unmarshalling
  # set.rb's tree a hundred times is the whole of what that costs.
  def test_a_source_parsed_before_answers_without_reading_the_cache_again
    source = "def memoized(a) = a + 1\n"
    first = ParseCache.parse(source, filepath: "memo.rb")
    File.delete(File.join(ParseCache.directory, "#{ParseCache.key(source, { filepath: "memo.rb" })}.marshal"))
    assert_same first, ParseCache.parse(source, filepath: "memo.rb")
  ensure
    ParseCache.memo.clear
  end

  def test_each_source_keeps_a_memo_of_its_own
    one = ParseCache.parse("memo_one = 1\n", filepath: "memo.rb")
    two = ParseCache.parse("memo_two = 2\n", filepath: "memo.rb")

    refute_same one, two
    assert_same one, ParseCache.parse("memo_one = 1\n", filepath: "memo.rb")
  ensure
    ParseCache.memo.clear
  end

  def test_a_result_read_back_answers_as_the_parse_did
    Dir.mktmpdir("ze0-parse-") do |dir|
      path = File.join(dir, "result.marshal")
      source = File.read(File.join(ROOT, "lib/ze0/hir/build.rb"))
      parsed = Prism.parse(source, filepath: "build.rb")
      ParseCache.write(path, Marshal.dump(parsed))
      read = ParseCache.read(path)
      assert parsed.value.inspect == read.value.inspect, "the tree read back differs"
      assert_equal parsed.value.location.start_line, read.value.location.start_line
      assert_equal parsed.comments.map(&:slice), read.comments.map(&:slice)
      assert_equal parsed.errors.map(&:message), read.errors.map(&:message)
    end
  end

  def test_a_file_that_does_not_read_back_is_a_miss
    Dir.mktmpdir("ze0-parse-") do |dir|
      path = File.join(dir, "result.marshal")
      assert_nil ParseCache.read(path)
      File.binwrite(path, Marshal.dump(Prism.parse("1"))[0, 40])
      assert_nil ParseCache.read(path)
      File.binwrite(path, "not marshal")
      assert_nil ParseCache.read(path)
      File.binwrite(path, Marshal.dump([1, 2]))
      assert_nil ParseCache.read(path)
    end
  end

  private

  # What a fresh `require "ze0/prism"` leaves standing, one fact a line.
  def compiler_process
    said = IO.popen(Ze0::Harness::Unbundled.env, [RbConfig.ruby, "-I#{ROOT}/lib", "-e", <<~RUBY], unsetenv_others: true, &:read)
      require "ze0/prism"
      gem = $LOAD_PATH.resolve_feature_path("prism").last
      puts Prism.method(:parse).source_location.first
      puts gem
      puts $LOADED_FEATURES.include?(File.join(File.dirname(gem), "prism/node.rb"))
      puts $LOADED_FEATURES.grep(/prism[.](bundle|so)\z/).inspect
    RUBY
    assert_predicate $?, :success?, "the child did not answer: #{said}"
    said
  end
end
