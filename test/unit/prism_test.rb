# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/prism_diff"
require_relative "../../tool/lib/zr/dev"
require_relative "../../lib/zr/ports"
require_relative "../../lib/zr/runtime/ext/prism/ruby"
require "stringio"

# Checks the pure-Ruby prism against ruby's C prism: the generated files
# match the vendored config.yml and templates, the Prism.dump writer
# matches the C byte for byte on every dump read back, the parser's
# dumps match the C dumps, and the C extension's entry points return
# the same objects as the C.
class PrismTest < Minitest::Test
  PrismDiff = Zr::Harness::PrismDiff

  # lib/zr/prism.rb names prism's directory by a literal path, so zr sees
  # it when it compiles zr. It must be the directory of the vendored gem.
  def test_the_load_path_names_the_vendored_prism
    rel = Zr::Ports.lib("prism").delete_prefix(File.join(ROOT, ""))

    assert_includes File.read(File.join(ROOT, "lib/zr/prism.rb")), %(File.expand_path("../../#{rel}", __dir__))
  end

  def test_the_generated_files_are_current
    out, ok = Checks.generate("prism")
    assert ok, out
  end

  def test_the_encoding_tables_are_current
    skip "no prism source: PRISM_SRC names a prism checkout or a #{Zr::Dev::PRISM} tree" unless Zr::Dev.prism?

    out, ok = Checks.generate("prism_encoding_tables")
    assert ok, out
  end

  # A comparison over thousands of cases runs as SHARDS tests over slices
  # of them, plus one test that checks the case count. Each test runs in
  # one worker. As one test, five thousand cases ran in one worker for two
  # minutes while seven workers were idle. The cases are listed once, here,
  # in the process that forks the workers. If the cases need a prism
  # checkout that this machine does not have, one test skips and says so.
  SHARDS = 8

  def self.compare(name, cases, at_least:, &check)
    unless cases
      define_method("test_#{name}") { skip "no prism checkout at #{PrismDiff::CHECKOUT}" }
      return
    end

    define_method("test_#{name}_has_its_cases") { assert_operator cases.size, :>, at_least }
    cases.each_slice((cases.size / SHARDS.to_f).ceil).with_index(1) do |slice, n|
      define_method("test_#{name}_#{n}_of_#{SHARDS}") { instance_exec(slice, &check) }
    end
  end

  def self.upstream_cases(...) = PrismDiff.upstream && PrismDiff.cases(...)

  compare("the_writer_writes_zrs_own_ruby_as_the_c_does", PrismDiff.cases(%w[lib]), at_least: 300) do |cases|
    assert_empty PrismDiff.writer(cases).first(5)
  end

  # The lexer without the parser: every fixture and error file lexes in
  # every mode and gives the C tokens, except where the parser changes the
  # lex state (lambda braces, `do` loops, labels, ignored newlines,
  # interpolation). No file raises.
  def test_lexer_matches_c_tokens_on_prism_fixtures_and_errors
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    failures, unsupported = PrismDiff.lex(cases)
    assert_empty failures.select { |_, why| why.include?("Error") }.first(5)
    assert_equal 0, unsupported
    assert_operator cases.size - failures.size, :>=, 4744
  end

  # The Ruby parser: Prism::Ruby.dump is equal to Prism.dump byte for byte,
  # on zr's own Ruby and on every fixture and error file under each syntax
  # version.
  compare("the_parser_dumps_zrs_own_ruby_as_the_c_does", PrismDiff.cases(%w[lib]), at_least: 300) do |cases|
    assert_empty PrismDiff.dump(cases).first(5)
  end

  compare("the_parser_dumps_prisms_fixtures_and_errors_as_the_c_does", upstream_cases(%w[fixtures errors]),
          at_least: 5000) do |cases|
    assert_empty PrismDiff.dump(cases).first(5)
  end

  # Broken sources (truncated, cut, or with a stray byte): the parser
  # recovers as the C does.
  compare("the_parser_dumps_broken_fixtures_as_the_c_does",
          upstream_cases(%w[fixtures errors], only: "**/*@4.1")&.then { |cases| PrismDiff.fuzz(cases, 2, 1) },
          at_least: 2500) do |cases|
    assert_empty PrismDiff.dump(cases).first(5)
  end

  compare("the_writer_writes_prisms_fixtures_and_errors_as_the_c_does", upstream_cases(%w[fixtures errors]),
          at_least: 5000) do |cases|
    assert_empty PrismDiff.writer(cases).first(5)
  end

  # Prism.parse, lex, parse_lex, parse_comments and parse_success? in Ruby:
  # every node, token, comment and diagnostic is equal to the C extension's,
  # down to the encoding and frozen state of each String.
  compare("entry_points_match_c_extension_on_prism_fixtures_and_errors",
          upstream_cases(%w[fixtures errors], only: "**/*@4.1"), at_least: 1200) do |cases|
    %i[parse lex parse_lex parse_comments parse_success?].each do |method|
      assert_empty PrismDiff.api(cases, method).first(5), method
    end
    %i[parse parse_lex].each do |method|
      assert_empty PrismDiff.api(cases, method, freeze: true).first(5), "#{method}, freeze: true"
    end
  end

  # Encodings from a magic comment or an option, invalid names, a BOM, a
  # shebang, and the errors bad options raise.
  def test_entry_points_match_c_for_encodings_and_options
    sources = ["# encoding: shift_jis\nx = \"\x82\xa0\"".b, "# -*- coding: binary -*-\n:\"\xff\"\n\"\xe9\"".b, "x = \"\xff\"".b,
               "\xEF\xBB\xBFputs 1".b, "#!/usr/bin/env ruby\n# encoding: euc-jp\nx".b, "def \xff; end".b, "x = 1\n__END__\nstuff"]
    options = [{}, { freeze: true }, { encoding: "Shift_JIS" }, { encoding: Encoding::EUC_JP, freeze: true }, { encoding: false },
               { command_line: "x", main_script: true }, { line: 10, filepath: "a
end
b.rb" }, { scopes: [%i[a b]] }]
    failures = sources.product(options, %i[parse lex parse_lex parse_comments parse_success? dump profile]).filter_map do |source, keywords, method|
      why = PrismDiff.call_difference(Prism, Prism::Ruby) { |prism| prism.public_send(method, source, **keywords) }
      "#{method} #{source.inspect} #{keywords}: #{why}" if why
    end
    bad = [[1, {}], ["x", { foo: 1 }], ["x", { version: "2.0" }], ["x", { version: 3 }], ["x", { encoding: 5 }],
           ["x", { command_line: "z" }], ["x", { command_line: "ae
end
z" }], ["x", { scopes: [1] }], ["x", { scopes: [["a"]] }],
           ["x", { scopes: [Prism::Scope.new([:a], [:x])] }], ["x", { line: "3" }], ["x", { line: 1.5 }], ["x", { line: 2**40 }],
           ["x", { line: 2**70 }], ["x", { line: Float::NAN }], ["x", { filepath: 3 }], ["x", { version: "3.4.99" }]]
    failures += bad.filter_map do |source, keywords|
      why = PrismDiff.call_difference(Prism, Prism::Ruby) { |prism| prism.parse(source, **keywords) }
      "parse #{source.inspect} #{keywords}: #{why}" if why
    end
    assert_empty failures.first(5)
  end

  # The _file entry points read a file, and raise for a missing file or a
  # directory. parse_stream reads more lines while the source is cut off.
  def test_file_and_stream_entry_points_match_c_extension
    Dir.mktmpdir("prism-files-") do |dir|
      File.binwrite(File.join(dir, "sjis.rb"), "# encoding: shift_jis\nx = \"\x82\xa0\"\n".b)
      File.write(File.join(dir, "plain.rb"), "x = 1\n")
      paths = %w[sjis.rb plain.rb missing.rb].map { |name| File.join(dir, name) } + [dir, File.join(dir, "plain.rb
end
junk"), 5]
      methods = %i[parse_file lex_file parse_lex_file parse_file_comments parse_file_success? parse_file_failure? dump_file profile_file]
      failures = paths.product(methods, [{}, { freeze: true, filepath: "other.rb" }]).filter_map do |path, method, keywords|
        why = PrismDiff.call_difference(Prism, Prism::Ruby) { |prism| prism.public_send(method, path, **keywords) }
        "#{method} #{path.inspect} #{keywords}: #{why}" if why
      end
      streams = ["x = 1\ny = 2\n", "foo(<<~EOS)\n  a\nEOS\nbar\n", "x = \"abc\ndef\"\nz\n", "a\n__END__\nb\n", "#{"x" * 5000}\n", ""]
      failures += streams.product([{}, { freeze: true }]).filter_map do |text, keywords|
        why = PrismDiff.call_difference(Prism, Prism::Ruby) { |prism| prism.parse_stream(StringIO.new(text), **keywords) }
        "parse_stream #{text[0, 20].inspect} #{keywords}: #{why}" if why
      end
      assert_empty failures.first(5)
    end
  end

  # Prism::Pack.parse and Prism::StringQuery's native halves.
  def test_pack_and_string_query_match_c_extension
    random = Random.new(5)
    letters = "CSLQJcsljqIinNvVUwDdFfEeGgAaZBbHhuMmPp@Xx%K _!<>*0123456789#\n".chars
    templates = Array.new(2000) { Array.new(random.rand(0..8)) { letters.sample(random: random) }.join }
    templates += ["", "C18446744073709551615", "C18446744073709551616", "C18446744073709551619", nil, 5]
    failures = templates.product(%i[pack unpack]).filter_map do |template, variant|
      why = PrismDiff.call_difference(Prism::Pack, Prism::Ruby::Pack) { |pack| pack.parse(:v3_2_0, variant, template) }
      "Pack.parse #{variant} #{template.inspect}: #{why}" if why
    end
    names = ["foo", "Foo", "foo?", "foo!", "foo=", "_1", "_0", "_12", "", "[]", "[]=", "<=>", "!", "a b", "é", "É", "Ωmega", "foo?x", "a
end
"]
    encodings = [Encoding::UTF_8, Encoding::BINARY, Encoding::US_ASCII, Encoding::Shift_JIS, Encoding::EUC_JP, Encoding::UTF_16LE]
    failures += names.product(encodings, %i[local? constant? method_name?]).filter_map do |name, encoding, method|
      string = name.dup.force_encoding(encoding)
      why = PrismDiff.call_difference(Prism::StringQuery, Prism::Ruby::StringQuery) { |query| query.public_send(method, string) }
      "StringQuery.#{method} #{string.inspect}: #{why}" if why
    end
    assert_empty failures.first(5)
  end

  # prism 1.9.0's own test suite on the Ruby port. A file that returns
  # before its tests, on a ruby whose own parser is prism, runs none.
  def test_prisms_own_test_suite_passes_on_the_ruby_port
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    runs = PrismDiff.upstream_tests(:ruby)
    assert_operator runs.count(&:passed?), :>=, 63
    failures = runs.reject { |run| run.passed? || run.tests.nil? }.map { |run| "#{run.file}\n#{run.output.lines.last(30).join}" }
    assert_empty failures.first(3)
  end

  # `Prism.lex_compat` reaches `Prism::Translation::Ripper::Lexer::State`,
  # which `prism/translation.rb` autoloads, so that file must be vendored.
  # Without it, the compiler's prism raises NameError. syntax_suggest lexes
  # with this call, and ruby's report for a file that does not parse goes
  # through syntax_suggest.
  def test_lex_compat_returns_same_tokens_as_gem_prism
    source = File.read(File.join(ROOT, "lib/zr/clock.rb"))
    tokens = lexed(source, "zr/prism")

    assert_operator tokens.lines.size, :>, 50
    assert_equal lexed(source, "prism"), tokens
  end

  private

  # The tokens that a fresh ruby with `feature` loaded makes from `source`.
  def lexed(source, feature)
    program = "require #{feature.inspect}\nputs Prism.lex_compat(ARGV[0]).value.map(&:inspect)\n"
    said = IO.popen(Zr::Harness::CleanEnv.env, [RbConfig.ruby, "-I#{ROOT}/lib", "-e", program, source],
                    unsetenv_others: true, err: %i[child out], &:read)
    assert_predicate $?, :success?, "the child did not lex with #{feature}: #{said}"
    said
  end
end
