# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"

# Compares the core's side of Regexp (runtime/core/regexp_pattern.rb and
# runtime/core/regexp/onig/*) under this ruby with Regexp.new, pattern
# by pattern. It checks each error from Onigmo and from ruby's
# preprocess (the text and the pattern after it), each warning (quiet
# and verbose), the group names, and the limits. onig_match_test and
# regexp_diff_test check matching.
Zr.require_onig
require File.join(ROOT, "runtime/core/regexp_pattern.rb")

class OnigParseTest < Minitest::Test
  Pattern = Regexp.const_get(:Pattern)

  ERRORS = [
    # onig errors, in regerror.c's order
    "a{", "[]", "[a", "a\\", "\\M", "\\C", "\\M-", "\\C-", "\\c", "[a-\\d]", "[\\d-z]", "*", "a**+", "+a", "{1}a", "(?i)*",
    ")", "a)", "(a", "(?", "(?<a", "(?z)", "(?Q:a)", "[[:foo:]]", "(?<=a*)", "(?<=a|bc*)", "(?<!a+)", "a{2,1}", "(?(",
    "(?(1a)b)", "(?(<n)b)", "a{100001}", "a{1,100001}", "\\99999999999", "[b-a]", "\\x{1234567890}", "\\1", "\\k<1>",
    "(?<a>x)\\2", "(?<a>x)(b)\\1", "\\k<>", "(?<>a)", "(?<1a>a)", "(?<a-b>a)", "\\k<nope>", "\\g<nope>", "\\k<-5>",
    "(?<a>x)(?<a>y)\\g<a>", "(?<a>\\g<a>)", "\\p{Foo}", "\\p{", "\\p{Alpha", "\\P{^Alpha", "\\x{110000}", "\\u{110000}",
    "\\uD800", "\\u{D800}", "\\u12", "\\u{}", "\\u{1 2", "\\xZ", "\\M-\\M-a", "\\C-\\c-a", "\\777", "(?#a", "(?~", "(?~|",
    "(?<a+>x)", "(?<a>x)\\k<a+1", "(?<a>x)\\k<a+x>", "[[:alpha:]", "[a&&", "[\\", "a{,", "(?-", "(?a-u)", "(?imxdau)",
    "\\R+*", "\\X{2,1}", "(?<a>)(?<a>)\\g<a>", "(?>a)*+", "a|*", "(|)*", "()\\g<2>", "\\g<-1>", "(a)\\g<+2>",
    # preprocess errors
    "\\u", "\\u{", "\\u{1234567}", "\\u{zz}", "\\xe3\\x81", "\\xff\\xfe", "\\M-\\C-\\M-a", "\\c\\c",
  ].freeze

  WARNINGS = [
    "[aa]", "[a-cb]", "[\\w\\d]", "[[:alpha:]a]", "(?:a*)*", "(?:a+)+", "(?:a?)*", "(?:a*)+", "(?:a+)?", "(?:a?)+",
    "(?:a{2})*", "a]", "[a-]", "[-a]", "[a-b-c]", "[]]", "\\q", "[\\q]", "[\\u3042\\u3042]", "(?:(?:a)*)*",
    "(?:a*?)*", "(?:a{1,3})+", "(?:a+?)?", "\\p{Alpha}\\p{Alpha}", "[\\p{Alpha}a]", "[\\x41A]", "(?x) a # c\n [aa]",
  ].freeze

  NAMES = [
    "(?<a>x)(?<b>y)(?<a>z)", "(?<a>x)(y)", "(x)(?<a>y)", "(?<日本>x)", "(?<a1_b>x)\\k<a1_b>", "(?<a>x)\\g<a>?",
    "(?<a>(?<b>x))\\k<b>", "(?<é>x)(?<e>y)",
  ].freeze

  def compile_in_ruby(pattern, options, verbose)
    out = []
    was = $VERBOSE
    $VERBOSE = nil
    Warning.singleton_class.class_eval do
      alias_method :warn_before_parse_test, :warn
      define_method(:warn) { |message, **| out << message.sub(/\A[^:]*:\d+: warning: /, "").chomp }
    end
    $VERBOSE = verbose
    re = Regexp.new(pattern, options)
    [:ok, re.names, re.source, out]
  rescue RegexpError, ArgumentError => e
    [:error, e.class, e.message.b]
  ensure
    $VERBOSE = nil
    Warning.singleton_class.class_eval do
      alias_method :warn, :warn_before_parse_test
      remove_method :warn_before_parse_test
    end
    $VERBOSE = was
  end

  def compile_in_core(pattern, options, verbose)
    _, _, compiled, warnings = Pattern.compile(pattern.dup.freeze, options)
    names = compiled.name_table ? compiled.name_table.keys.map { |name| name.dup.force_encoding(pattern.encoding) } : []
    [:ok, names, pattern, warnings.rows.reject { |row| row.verbose && !verbose }.map { |row| row.text }]
  rescue RegexpError, ArgumentError => e
    [:error, e.class, e.message.b]
  end

  def assert_like_ruby(pattern, options = 0)
    [false, true].each do |verbose|
      want = compile_in_ruby(pattern, options, verbose)
      got = compile_in_core(pattern, options, verbose)
      assert_equal want, got, "/#{pattern}/ options #{options}#{verbose ? " verbose" : ""}"
    end
  end

  def test_error_message_matches_ruby_for_each_pattern
    ERRORS.each do |pattern|
      [0, Regexp::IGNORECASE | Regexp::EXTENDED].each { |options| assert_like_ruby(pattern, options) }
    end
  end

  def test_errors_show_the_pattern_as_messages_show_it
    ["(日", "(é/", "(\x01\t", "(a/b", "(\\/", "(\u{1F600}"].each { |pattern| assert_like_ruby(pattern) }
    assert_like_ruby("(\xff".b)
    assert_like_ruby("(\xe9".dup.force_encoding("ISO-8859-1"))
    assert_like_ruby("(", Regexp::MULTILINE | Regexp::IGNORECASE | Regexp::EXTENDED)
  end

  def test_warnings_quiet_and_verbose
    WARNINGS.each { |pattern| assert_like_ruby(pattern) }
    assert_like_ruby("[" + ("aa" * 150) + "]")
  end

  def test_group_names_in_definition_order
    NAMES.each { |pattern| assert_like_ruby(pattern) }
  end

  # Onigmo's parse depth limit (4096) is deeper than the recursive parser
  # can go on this ruby's VM stack. Thus the nesting cases run in a child
  # process with a larger stack. The corpus tests the stack of the
  # compiled runtime.
  def test_the_ceilings
    assert_like_ruby("()" * 32_767)
    assert_like_ruby("()" * 32_768)
    assert_like_ruby("a{100000}")
    assert_like_ruby("a{100001}")
    script = <<~'RUBY'
      require "./lib/zr/runtime"
      Zr.require_onig
      require "./runtime/core/regexp_pattern.rb"
      pattern = Regexp.const_get(:Pattern)
      [4095, 4096, 4097].each do |depth|
        [["(", ")"], ["(?:", ")"], ["[", "]"]].each do |open, close|
          text = open * depth + "a" + close * depth
          want = begin; Regexp.new(text); "ok"; rescue RegexpError => e; e.message; end
          got = begin; pattern.compile(text, 0); "ok"; rescue RegexpError => e; e.message; end
          puts want == got ? "same" : "DIFF #{open}x#{depth}: #{want[0, 60]} / #{got[0, 60]}"
        end
      end
    RUBY
    out = IO.popen({ "RUBY_THREAD_VM_STACK_SIZE" => (256 << 20).to_s }, [RbConfig.ruby, "-e", script], chdir: ROOT, err: %i[child out], &:read)
    assert_equal ["same"] * 9, out.lines.map(&:chomp), out
  end

  def test_the_n_option_and_fixed_encodings
    [["a", Regexp::NOENCODING], ["あ", Regexp::NOENCODING], ["\\xff", Regexp::NOENCODING], ["\\u3042", Regexp::NOENCODING],
     ["a", Regexp::FIXEDENCODING], ["\\xff", 0], ["\\p{Hiragana}", Regexp::NOENCODING]].each do |pattern, options|
      assert_like_ruby(pattern, options)
    end
  end
end
