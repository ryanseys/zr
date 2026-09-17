# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/prism"
require_relative "../support/harness/prism_diff"

# The host parses with the Ruby port, and keeps each parse in the cache
# (lib/ze0/parse_cache.rb). The cache fails closed: every input of a parse
# is in the key, and a file that does not read back is a miss.
class ParseCacheTest < Minitest::Test
  ParseCache = Ze0::ParseCache

  def test_the_host_parses_with_the_ruby_port_and_the_vendored_ruby_half
    assert_equal File.join(ROOT, "rt/ext/prism/prism.rb"), Prism.method(:parse).source_location.first
    assert_equal File.join(ROOT, "vendor/ext/prism/lib/prism.rb"), $LOAD_PATH.resolve_feature_path("prism").last
    assert_includes $LOADED_FEATURES, File.join(ROOT, "vendor/ext/prism/lib/prism/node.rb")
    assert_empty $LOADED_FEATURES.grep(/prism\.(bundle|so)\z/)
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
end
