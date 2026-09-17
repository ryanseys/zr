# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/harness/prism_diff"
require_relative "../../rt/ext/prism/ruby"
require "stringio"

# The pure-Ruby prism held to ruby's C prism (tools/prism_diff.rb): its
# generated files current with the vendored config.yml and templates,
# Prism.dump's writer equal to the C byte for byte on every dump read back,
# the parser's dumps equal to the C's, and the C extension's entry points
# answering as the C's do, object for object.
class PrismTest < Minitest::Test
  PrismDiff = Ze0::Harness::PrismDiff

  def test_the_generated_files_are_current
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tools/prism_generate.rb"), "--check"], err: %i[child out], &:read)
    assert $?.success?, out
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tools/prism_encoding_tables.rb"), "--check"], err: %i[child out], &:read)
    assert $?.success?, out
  end

  def test_the_writer_writes_ze0s_own_ruby_as_the_c_does
    cases = PrismDiff.cases(%w[rt lib])
    assert_operator cases.size, :>, 300
    assert_empty PrismDiff.writer(cases).first(5)
  end

  # The lexer with no parser behind it: every fixture and error file lexes
  # in every mode and gives C's tokens, except where the parser moves the
  # lex state (lambda braces, `do` loops, labels, ignored newlines,
  # interpolation), and none raises.
  def test_the_lexer_alone_lexes_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    failures, unsupported = PrismDiff.lex(cases)
    assert_empty failures.select { |_, why| why.include?("Error") }.first(5)
    assert_equal 0, unsupported
    assert_operator cases.size - failures.size, :>=, 4744
  end

  # The Ruby parser: Prism::Ruby.dump equal to Prism.dump byte for byte, on
  # ze0's own Ruby and on every fixture and error file under each syntax
  # version.
  def test_the_parser_dumps_ze0s_own_ruby_as_the_c_does
    cases = PrismDiff.cases(%w[rt lib])
    assert_operator cases.size, :>, 300
    assert_empty PrismDiff.dump(cases).first(5)
  end

  def test_the_parser_dumps_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    assert_operator cases.size, :>, 5000
    assert_empty PrismDiff.dump(cases).first(5)
  end

  # Broken sources: truncated, cut or with a stray byte, the parser recovers
  # as the C does.
  def test_the_parser_dumps_broken_fixtures_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.fuzz(PrismDiff.cases(%w[fixtures errors], only: "**/*@4.1"), 2, 1)
    assert_operator cases.size, :>, 2500
    assert_empty PrismDiff.dump(cases).first(5)
  end

  def test_the_writer_writes_prisms_fixtures_and_errors_as_the_c_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors])
    assert_operator cases.size, :>, 5000
    assert_empty PrismDiff.writer(cases).first(5)
  end

  # Prism.parse, lex, parse_lex, parse_comments and parse_success? in Ruby:
  # every node, token, comment and diagnostic equal to the C extension's,
  # down to each String's encoding and frozenness.
  def test_the_entry_points_answer_prisms_fixtures_and_errors_as_the_c_extension_does
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    cases = PrismDiff.cases(%w[fixtures errors], only: "**/*@4.1")
    assert_operator cases.size, :>, 1200
    %i[parse lex parse_lex parse_comments parse_success?].each do |method|
      assert_empty PrismDiff.api(cases, method).first(5), method
    end
    %i[parse parse_lex].each do |method|
      assert_empty PrismDiff.api(cases, method, freeze: true).first(5), "#{method}, freeze: true"
    end
  end

  # Encodings from a magic comment or an option, invalid names, a BOM, a
  # shebang, and the errors bad options raise.
  def test_the_entry_points_read_encodings_and_options_as_the_c_extension_does
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
  # directory; parse_stream reads lines again while the source is cut.
  def test_the_file_and_stream_entry_points_read_as_the_c_extension_does
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
  def test_pack_and_string_query_answer_as_the_c_extension_does
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

  # prism 1.9.0's own test suite on the Ruby port (tools/prism_upstream_tests.rb
  # runs it beside the C extension). A file that returns before its tests,
  # on a ruby whose own parser is prism, runs none.
  def test_prisms_own_test_suite_passes_on_the_ruby_port
    skip "no prism checkout at #{PrismDiff::CHECKOUT}" unless PrismDiff.upstream

    runs = PrismDiff.upstream_tests(:ruby)
    assert_operator runs.count(&:passed?), :>=, 63
    failures = runs.reject { |run| run.passed? || run.tests.nil? }.map { |run| "#{run.file}\n#{run.output.lines.last(30).join}" }
    assert_empty failures.first(3)
  end
end
