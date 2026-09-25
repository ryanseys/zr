# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require_relative "../../lib/zr/prism"
require_relative "../../lib/zr/parse_cache"
require_relative "../../lib/zr/runtime"
require_relative "../support/harness/prism_diff"

# The host parses with the Ruby port and keeps each parse in the cache
# (lib/zr/parse_cache.rb). The cache fails closed: the key contains every
# input of a parse, and a file that does not read back is a miss.
class ParseCacheTest < Minitest::Test
  ParseCache = Zr::ParseCache

  # The facts come from a child process, not from this process. A process
  # that loaded ruby's own C prism first keeps it (see `lib/zr/prism.rb`).
  # This tier includes the harness that loads the C prism on purpose, so
  # this process does not show what the compiler uses. A fresh ruby that
  # requires `zr/prism` is the same case as the compiler.
  def test_host_parses_with_ruby_port_and_no_c_extension
    parse, gem, node, native = compiler_process.lines(chomp: true)

    assert_equal File.join(ROOT, "runtime/ext/prism/prism.rb"), parse
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

  def test_parser_files_include_port_backend_and_gem_ruby_files
    files = ParseCache.parser_files
    [
      "runtime/ext/prism/ruby/parser/core.rb", "runtime/ext/prism/ruby/lexer.rb", "runtime/ext/prism/ruby/ast.rb", "runtime/ext/prism/prism.rb",
      "lib/zr/prism_shim/prism/prism.rb", "lib/zr/prism.rb", "lib/zr/parse_cache.rb"
    ].each { |path| assert_includes files, File.join(ROOT, path) }
    gem = $LOAD_PATH.resolve_feature_path("prism").last
    assert_includes files, gem
    assert_includes files, File.join(File.dirname(gem), "prism/node.rb")
  end

  # The parser part of the key is the path and digest of each file. Thus a
  # compiled compiler, which contains the digests of its source files but
  # not the files, makes the same key from its own set.
  def test_the_parser_key_is_the_digest_of_each_parser_file
    digests = ParseCache.parser_files.to_h { |file| [file, Digest::SHA256.hexdigest(File.binread(file))] }
    assert_equal ParseCache.parser, ParseCache.parser_key(digests)
    assert_equal ParseCache.parser, ParseCache.parser_key(digests.to_a.reverse.to_h)

    port = File.join(ROOT, "runtime/ext/prism/ruby/lexer.rb")
    refute_equal ParseCache.parser, ParseCache.parser_key(digests.merge(port => "0" * 64))
    refute_equal ParseCache.parser, ParseCache.parser_key(digests.except(port))
  end

  def test_a_path_is_a_parser_file_by_the_patterns_alone
    ParseCache.parser_files.each { |file| assert ParseCache.parser_file?(file), file }
    refute ParseCache.parser_file?(File.join(ROOT, "lib/zr/runtime.rb"))
    refute ParseCache.parser_file?(File.join(ROOT, "runtime/ext/prism.rb"))
    assert ParseCache.parser_file?(File.join(ROOT, "runtime/ext/prism/ruby/parser/core.rb"))
  end

  # The process parses with the port that it loaded, and the key identifies
  # the files on disk when the digest was taken. If a port file changes
  # after that, the build does not write a parse under the old key.
  def test_write_raises_when_a_parser_file_changed
    ParseCache.parser
    stamps = ParseCache.instance_variable_get(:@stamps)
    file = stamps.keys.first
    ParseCache.instance_variable_set(:@stamps, stamps.merge(file => [0, 0]))
    Dir.mktmpdir("zr-parse-") do |dir|
      error = assert_raises(Zr::SourceChanged) { ParseCache.write(File.join(dir, "x.marshal"), "x") }
      assert_includes error.message, file
      refute File.exist?(File.join(dir, "x.marshal"))
    end
  ensure
    ParseCache.instance_variable_set(:@stamps, stamps)
  end

  # A build keeps what it derives from a tree (error_highlight's spots)
  # next to the parse, under the parse's key and the digest of the code
  # that derives it.
  def test_a_derived_form_is_made_once_and_read_back_after
    source = "derived_#{Process.pid} = 1\n"
    options = { filepath: "derived.rb", line: 1 }
    spotter = [File.join(ROOT, "lib/zr/hir/spots.rb")]
    made = 0
    first = ParseCache.derived("spots", source, options, spotter) { made += 1; "1 n - 1 0 1 5\n" }
    again = ParseCache.derived("spots", source, options, spotter) { made += 1; "other" }

    assert_equal 1, made
    assert_equal first, again
    assert_equal Encoding::UTF_8, again.encoding
    assert_equal "other", ParseCache.derived("spots", source, options, spotter + [File.join(ROOT, "lib/zr/hir.rb")]) { "other" }
  end

  def test_derived_form_is_not_cached_when_its_maker_is_missing
    source = "underived_#{Process.pid} = 1\n"
    options = { filepath: "derived.rb", line: 1 }
    missing = [File.join(ROOT, "lib/zr/no_such_maker.rb")]
    assert_equal "a", ParseCache.derived("spots", source, options, missing) { "a" }
    assert_equal "b", ParseCache.derived("spots", source, options, missing) { "b" }
  end

  # A second parse of a source in the same process returns the tree that
  # the memo contains, and reads no file. A worker of the spec tier runs a
  # hundred examples that each require "set". Without the memo, almost all
  # of that time goes to unmarshalling the tree of set.rb a hundred times.
  def test_parse_returns_memoized_tree_without_reading_the_cache
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

  # The memo has a size limit. A build parses each file once, and without
  # a limit the memo keeps every tree until the build ends.
  def test_memo_drops_least_recently_used_entry_when_full
    memo = Zr::ParseCache::Memo.new(10)
    memo.keep("a", :first, 4)
    memo.keep("b", :second, 4)
    memo["a"]
    memo.keep("c", :third, 4)

    assert_nil memo["b"]
    assert_equal :first, memo["a"]
    assert_equal :third, memo["c"]
    assert_equal 8, memo.bytes
  end

  def test_memo_does_not_keep_an_entry_larger_than_its_limit
    memo = Zr::ParseCache::Memo.new(10)
    memo.keep("small", :kept, 4)

    assert_equal :huge, memo.keep("huge", :huge, 11)
    assert_nil memo["huge"]
    assert_equal :kept, memo["small"]
  end

  def test_read_returns_the_tree_that_write_wrote
    Dir.mktmpdir("zr-parse-") do |dir|
      path = File.join(dir, "result.marshal")
      source = File.read(File.join(ROOT, "lib/zr/hir/build.rb"))
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
    Dir.mktmpdir("zr-parse-") do |dir|
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

  # What a fresh `require "zr/prism"` loads, one fact on each line.
  def compiler_process
    said = IO.popen(Zr::Harness::CleanEnv.env, [RbConfig.ruby, "-I#{ROOT}/lib", "-e", <<~RUBY], unsetenv_others: true, &:read)
      require "zr/prism"
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
