# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require_relative "../../lib/zr/cli"

# ruby's switches, as `zr` reads them when it acts as a ruby
# (lib/zr/cli/ruby_options.rb).
class RubyOptionsTest < Minitest::Test
  RubyOptions = Zr::CLI::RubyOptions

  # The test's own environment (bundler's RUBYOPT) must not count.
  def parse(*argv, env: {}) = RubyOptions.parse(argv, env)

  def test_the_script_ends_the_switches_and_the_rest_is_argv
    options = parse("-w", "app.rb", "-x", "--", "y")

    assert_equal ["app.rb", ["-x", "--", "y"]], [options.script, options.args]
  end

  def test_each_e_is_a_line_and_every_word_after_it_is_argv
    options = parse("-e", "p 1", "-ep 2", "a.rb", "b")

    assert_equal "p 1\np 2\n", options.inline_source
    assert_nil options.script
    assert_equal ["a.rb", "b"], options.args
  end

  def test_a_lone_dash_is_standard_input_and_a_double_dash_ends_the_switches
    assert_equal ["-", ["a"]], parse("-", "a").then { |o| [o.script, o.args] }
    assert_equal ["-w", ["a"]], parse("--", "-w", "a").then { |o| [o.script, o.args] }
    assert_nil parse.script
  end

  def test_letters_cluster_until_one_takes_the_rest_of_the_word
    options = parse("-lane", "print $F[0]", "in.txt")

    assert_equal "nale", options.switches.command_line
    assert_equal "print $F[0]\n", options.inline_source
    assert_equal ["in.txt"], options.args
  end

  def test_p_implies_n_and_x_takes_a_directory
    options = parse("-px/tmp", "s.rb")

    assert_equal "pnx", options.switches.command_line
    assert_equal ["/tmp"], options.chdirs
  end

  def test_i_and_r_take_the_rest_of_the_word_or_the_next_word
    options = parse("-Ilib", "-I", "vendor", "-rjson", "-r", "set", "-e", "1")

    assert_equal %w[lib vendor], options.includes
    assert_equal %w[json set], options.requires
  end

  def test_one_i_takes_a_list_and_keeps_a_dot_slash_directory_as_given
    options = parse("-I", "./\u3042:./b::lib", "-e", "1")

    assert_equal ["./\u3042", "./b", "lib"], options.includes
    assert_includes options.prelude.to_s, %(#{"./\u3042".inspect}.freeze, "./b".freeze, #{File.expand_path("lib").inspect}.freeze)
  end

  def test_the_prelude_sets_what_each_switch_sets_in_rubys_order
    prelude = parse("-W0", "-d", "-I/l", "-rjson", "-l", "-s", "-Eascii-8bit:utf-8", "s.rb").prelude.to_s.lines(chomp: true)

    assert_equal ["$VERBOSE = true", "$DEBUG = true"], prelude.first(2)
    assert_includes prelude, '$LOAD_PATH.unshift("/l".freeze)'
    assert_includes prelude, '$\\ = "\n"'
    assert_operator prelude.index('require "json"'), :<, prelude.index('Encoding.send(:store_default, 0, "ASCII-8BIT")')
    assert_includes prelude, 'Encoding.send(:store_default, 1, "UTF-8")'
  end

  def test_no_switch_that_sets_anything_gives_no_prelude
    assert_nil parse("-e", "1").prelude
    assert_nil parse("x.rb").prelude
  end

  def test_w_levels_set_verbose_and_the_last_one_wins
    {
      %w[-W0] => "$VERBOSE = nil", %w[-W1] => "$VERBOSE = false", %w[-W2] => "$VERBOSE = true", %w[-W] => "$VERBOSE = true",
      %w[-w] => "$VERBOSE = true", %w[-w -W0] => "$VERBOSE = nil", %w[--verbose] => "$VERBOSE = true"
    }.each do |argv, line|
      assert_equal line, parse(*argv, "x.rb").prelude.to_s.lines.first.chomp, argv.inspect
    end
  end

  # The command line's warning level wins over RUBYOPT's.
  def test_the_command_line_level_wins_over_rubyopt
    { %w[-W1] => "$VERBOSE = false", %w[-W0] => "$VERBOSE = nil" }.each do |argv, line|
      assert_equal line, parse(*argv, "x.rb", env: { "RUBYOPT" => "-w" }).prelude.to_s.lines.first.chomp, argv.inspect
    end
    assert_equal "$VERBOSE = true", parse("-w", "x.rb", env: { "RUBYOPT" => "-W0" }).prelude.to_s.lines.first.chomp
    assert_equal "$VERBOSE = true", parse("x.rb", env: { "RUBYOPT" => "-w" }).prelude.to_s.lines.first.chomp
  end

  # -Wx is -W; -W2 with -U, and -w with -E, set the encodings with no warning.
  def test_wx_is_w_and_a_warning_level_leaves_the_encodings_quiet
    assert_equal "$VERBOSE = true", parse("-Wx", "x.rb").prelude.to_s.lines.first.chomp
    assert_equal [nil, "UTF-8", []], parse("-W2", "-U", "x.rb").then { |o| [o.external, o.internal, o.warnings] }
    assert_equal ["UTF-8", "Windows-31J", []], parse("-w", "-Eutf-8:Windows-31J", "x.rb").then { |o| [o.external, o.internal, o.warnings] }
  end

  # --debug names ruby's debug features, by prefix and in any case; an
  # unknown name warns, and --debug- alone is no option.
  def test_debug_switch_names
    assert parse("--debug=frozen", "x.rb").switches.debug_frozen_string_literal
    unknown = ->(name) { ["zr: warning: unknown argument for --debug: '#{name}'", "zr: warning: debug features are [frozen_string_literal]."] }
    assert_equal unknown["bar"], parse("--debug=FROZEN-STRING-LITERAL,bar", "x.rb").warnings
    assert_equal unknown["foo"], parse("--debug-foo", "x.rb").warnings
    assert_equal "invalid option --debug-  (-h will show valid options)", assert_raises(RubyOptions::Invalid) { parse("--debug-", "x.rb") }.message
  end

  # The backtrace limit is a long; a larger one is refused.
  def test_backtrace_limit_takes_a_long
    assert_includes parse("--backtrace-limit=9223372036854775807", "x.rb").prelude.to_s, "Primitive.zr_backtrace_limit_set(9223372036854775807)"
    assert_equal "wrong limit for backtrace length",
                 assert_raises(RubyOptions::Invalid) { parse("--backtrace-limit=9223372036854775808", "x.rb") }.message
  end

  def test_w_with_a_category_turns_only_it
    assert_equal ["Warning[:deprecated] = false"], parse("-W:no-deprecated", "x.rb").prelude.to_s.lines(chomp: true)
    assert_equal ["Warning[:performance] = true"], parse("-W:perf", "x.rb").prelude.to_s.lines(chomp: true)
    assert_equal ["zr: warning: unknown warning category: 'bogus'"], parse("-W:bogus", "x.rb").warnings
  end

  def test_zero_sets_the_record_separator_as_proc_0_option
    { "-0" => '$/ = "\x00".b.freeze', "-00" => '$/ = "".freeze', "-0777" => "$/ = nil", "-012" => '$/ = "\n".b.freeze' }.each do |switch, line|
      assert_equal line, parse(switch, "x.rb").prelude.to_s.chomp, switch
    end
  end

  def test_l_takes_the_record_separator_read_before_it
    assert_includes parse("-0777", "-l", "x.rb").prelude.to_s.lines(chomp: true), '$\ = nil'
  end

  def test_features_match_by_the_start_of_each_word
    switches = parse("--disable-gems", "--enable=frozen-string-literal", "x.rb").switches

    assert_equal [false, true], [switches.gems, switches.frozen_string_literal]
    assert_equal [false, false], parse("--disable=g,f-s-l", "x.rb").switches.then { |s| [s.gems, s.frozen_string_literal] }
    assert parse("--disable", "all", "--enable=frozen", "x.rb").switches.frozen_string_literal
    # --disable=jit cancels a JIT; --yjit still warns, as ruby.c does without YJIT.
    assert_equal 1, parse("--disable-jit", "--yjit", "x.rb").warnings.size
    assert_equal 2, parse("--enable=bogus", "x.rb").warnings.size
  end

  def test_s_and_inplace_and_split_set_their_globals
    prelude = parse("-s", "-i.bak", "-a", "-n", "x.rb").prelude.to_s

    assert_includes prelude, '$-i = ARGF.inplace_mode = ".bak"'
    assert_includes prelude, "$-a = true"
    assert_includes prelude, RubyOptions::S_FLAG
    assert_includes parse("-i", "x.rb").prelude.to_s, '$-i = ARGF.inplace_mode = ""'
  end

  def test_the_shebang_line_adds_its_switches
    options = parse("x.rb")
    options.shebang!("#!/usr/bin/env ruby -w -s\np 1\n")
    plain = parse("x.rb").tap { |o| o.shebang!("#!/bin/sh -w\n") }

    assert_includes options.prelude.to_s, "$VERBOSE = true"
    assert options.sflag
    assert_nil plain.prelude
  end

  def test_rubyopt_adds_its_switches_after_the_command_lines
    options = parse("-I/a", "-e", "1", env: { "RUBYOPT" => " -w  Ib -rjson " })

    assert_equal ["/a", "b"], options.includes
    assert_equal ["json"], options.requires
    assert_equal "$VERBOSE = true", options.prelude.to_s.lines.first.chomp
    assert_nil parse("--disable=rubyopt", "-e", "1", env: { "RUBYOPT" => "-w" }).prelude
  end

  def test_rubyopt_takes_only_the_switches_that_change_how_a_program_runs
    assert_equal "invalid switch in RUBYOPT: -e", assert_raises(RubyOptions::Invalid) { parse("x.rb", env: { "RUBYOPT" => "-e" }) }.message
    assert_equal "invalid switch in RUBYOPT: --version",
                 assert_raises(RubyOptions::Invalid) { parse("x.rb", env: { "RUBYOPT" => "--version" }) }.message
  end

  def test_rubylib_comes_after_the_include_directories_as_given_and_frozen
    prelude = parse("-I/inc", "x.rb", env: { "RUBYLIB" => "/a: b :" }).prelude.to_s

    assert_includes prelude, '$LOAD_PATH.unshift("/inc".freeze, "/a".freeze, " b ".freeze)'
  end

  def test_rubylib_takes_bytes_that_are_no_text
    prelude = parse("x.rb", env: { "RUBYLIB" => "/a:\xFF:/b".b }).prelude.to_s

    assert_includes prelude, '"/a".freeze, "\xFF".freeze, "/b".freeze'
  end

  def test_rubyopt_sets_only_what_the_command_line_did_not
    options = parse("-Eutf-8", "-KU", "x.rb", env: { "RUBYOPT" => "-Eus-ascii -KN" })

    assert_equal ["UTF-8", "UTF-8"], [options.external, options.switches.source_encoding]
    options = parse("--enable-frozen-string-literal", "--backtrace-limit=1", "x.rb",
                    env: { "RUBYOPT" => "--disable-frozen-string-literal --backtrace-limit=5 -W:no-deprecated" })

    assert options.switches.frozen_string_literal
    assert_includes options.prelude.to_s, "Primitive.zr_backtrace_limit_set(1)"
    assert_includes options.prelude.to_s, "Warning[:deprecated] = false"
    assert_includes parse("x.rb", env: { "RUBYOPT" => "-Eascii" }).external, "ASCII"
  end

  def test_k_sets_the_source_encoding_and_the_external_one
    options = parse("-Ke", "x.rb")

    assert_equal ["EUC-JP", "EUC-JP"], [options.switches.source_encoding, options.external]
    assert_equal "EUC-JP", options.switches.parse_options(true)[:encoding]
    assert_nil options.switches.parse_options(false)[:encoding]
  end

  def test_an_encoding_set_twice_must_be_the_same
    assert_equal "UTF-8", parse("-U", "-U", "-E:utf-8", "x.rb").internal
    assert_equal "default_internal already set to UTF-8", assert_raises(RubyOptions::Invalid) { parse("-U", "-E:ascii", "x.rb") }.message
    assert_equal "default_internal already set to ascii", assert_raises(RubyOptions::Invalid) { parse("-Eascii:ascii", "-U", "x.rb") }.message
    assert_equal "default_external already set to EUC-JP", assert_raises(RubyOptions::Invalid) { parse("-Ke", "-Eascii", "x.rb") }.message
  end

  def test_k_sets_the_external_encoding_only_where_nothing_set_it
    options = parse("-Eus-ascii", "-KN", "x.rb")

    assert_equal ["US-ASCII", "ASCII-8BIT"], [options.external, options.switches.source_encoding]
    assert_equal "EUC-JP", parse("-Ks", "-Ke", "x.rb").switches.source_encoding
    assert_equal "Windows-31J", parse("-Ks", "-Ke", "x.rb").external
  end

  # zr is a ruby built without JIT support: each JIT switch, with its
  # options or not, warns as ruby.c does then, and turns nothing on.
  def test_jit_switches_warn_as_a_ruby_built_without_jit_support
    yjit = "zr: warning: Ruby was built without YJIT support. You may need to install rustc and configure with --enable-yjit to build Ruby with YJIT."
    zjit = "zr: warning: Ruby was built without ZJIT support. You may need to install rustc to build Ruby with ZJIT."
    assert_equal ["zr: warning: Ruby was built without JIT support"], parse("--jit", "x.rb").warnings
    assert_equal [yjit], parse("--yjit", "x.rb").warnings
    assert_equal [yjit], parse("--yjit-stats=quiet", "x.rb").warnings
    assert_equal [yjit], parse("--yjit=x", "x.rb").warnings
    assert_equal [zjit], parse("--zjit-call-threshold=2", "x.rb").warnings
    assert_equal [yjit, zjit], parse("--yjit", "--zjit", "x.rb").warnings
    assert_empty parse("x.rb").warnings
  end

  def test_k_warns_under_w_only
    assert_equal ["zr: warning: -K is specified; it is for 1.8 compatibility and may cause odd behavior"], parse("-wKe", "x.rb").warnings
    assert_empty parse("-Ke", "x.rb").warnings
    assert_empty parse("-Ke", "-W0", "x.rb").warnings
  end

  def test_backtrace_limit_sets_the_limit_and_did_you_mean_can_be_disabled
    assert_includes parse("--backtrace-limit=2", "x.rb").prelude.to_s, "Primitive.zr_backtrace_limit_set(2)"
    assert_includes parse("--backtrace-limit", "-1", "x.rb").prelude.to_s, "Primitive.zr_backtrace_limit_set(-1)"
    assert_raises(RubyOptions::Invalid) { parse("--backtrace-limit=-2", "x.rb") }
    assert_equal "missing argument for --backtrace-limit", assert_raises(RubyOptions::Invalid) { parse("--backtrace-limit=", "1") }.message
    assert_includes parse("--disable=did_you_mean", "x.rb").prelude.to_s, "Object.send(:remove_const, :DidYouMean)"
    assert_includes parse("--disable-error_highlight", "x.rb").prelude.to_s, "Object.send(:remove_const, :ErrorHighlight)"
    # Without gems no autoload is made, so none is removed.
    refute_includes parse("--disable=gems", "x.rb").prelude.to_s, "remove_const"
  end

  # ruby_set_crash_report: the template replaces RUBY_CRASH_REPORT in the
  # program; RUBYOPT may give it, and it needs a value.
  def test_crash_report_names_where_a_bug_report_goes
    assert_includes parse("--crash-report=%p.log", "x.rb").prelude.to_s, 'Primitive.zr_crash_report_set("%p.log")'
    assert_includes parse("--crash-report", "|/usr/bin/tee r.log", "x.rb").prelude.to_s, 'Primitive.zr_crash_report_set("|/usr/bin/tee r.log")'
    assert_includes parse("x.rb", env: { "RUBYOPT" => "--crash-report=r.log" }).prelude.to_s, 'Primitive.zr_crash_report_set("r.log")'
    refute_includes parse("x.rb").prelude.to_s, "zr_crash_report_set"
    assert_equal "missing argument for --crash-report", assert_raises(RubyOptions::Invalid) { parse("--crash-report=", "x.rb") }.message
    assert_equal "missing argument for --crash-report", assert_raises(RubyOptions::Invalid) { parse("--crash-report") }.message
  end

  def test_zrs_own_flags_go_to_zr
    assert_equal %w[--trace --allow-runtime-require], parse("--trace", "--allow-runtime-require", "x.rb").zr
  end

  def test_a_switch_that_ruby_rejects_raises
    {
      %w[-q] => "invalid option -q  (-h will show valid options)",
      %w[--bogus] => "invalid option --bogus  (-h will show valid options)",
      %w[-e] => "no code specified for -e",
      %w[-E] => "missing argument for -E",
      %w[-E bogus] => "unknown encoding name - bogus",
      %w[--encoding] => "missing argument for --encoding",
      %w[--encoding=] => "missing argument for --encoding",
      %w[--dump] => "missing argument for --dump",
      %w[-0 --dump] => "missing argument for --dump",
      ["-\rx"] => "invalid option -\\r  (-h will show valid options)",
      ["-\x01"] => "invalid option -\\x01  (-h will show valid options)",
      ["-\e"] => "invalid option -\\e  (-h will show valid options)",
      ["-\x7f"] => "invalid option -\\c?  (-h will show valid options)",
      ["-é"] => "invalid option -é  (-h will show valid options)"
    }.each do |argv, message|
      error = assert_raises(RubyOptions::Invalid, argv.inspect) { parse(*argv) }
      assert_equal message, error.message
    end
  end

  def test_what_zr_cannot_do_is_refused_and_what_changes_nothing_is_taken
    assert_equal "--dump=insns (zr compiles to machine code, not to YARV instructions) is not supported", parse("--dump=parsetree,i", "x.rb").refused
    assert_nil parse("-y", "--jit", "--yjit-call-threshold=1", "--crash-report=x", "--parser=prism", "x.rb").refused
    assert_nil parse("--debug-frozen-string-literal", "--debug=frozen-string-literal", "x.rb").refused
    refute parse("--debug-frozen-string-literal", "x.rb").debug
    assert parse("--debug", "x.rb").debug
  end

  # -c, -y, --yydebug and --dump set the items that print in place of a
  # run, in ruby's order; an item's name can be the start of it.
  def test_the_dump_items_print_in_place_of_a_run
    assert_equal %i[syntax], parse("-c", "-e", "1").dumps
    assert_equal %i[yydebug], parse("-y", "x.rb").dumps
    assert_equal %i[yydebug], parse("--yydebug", "x.rb").dumps
    assert_equal %i[yydebug syntax parsetree], parse("--dump=p,s", "--dump", "y", "x.rb").dumps
    assert_equal %i[parsetree], parse("--dump=PARSETREE+comment", "x.rb").dumps
    refute_predicate parse("x.rb"), :dumps?
  end

  # The items that are not dumps are the switches of the same name.
  def test_the_version_copyright_and_usage_items_are_their_switches
    assert parse("--dump=version", "x.rb").version_only
    assert parse("--dump=copyright").copyright
    assert_predicate parse("--dump=usage"), :help?
    refute_predicate parse("--dump=usage"), :long_help?
    assert_predicate parse("--dump=h"), :long_help?
  end

  # -h is the short usage and --help the long one. As in ruby, --help wins
  # in either order.
  def test_h_is_the_short_usage_and_help_wins
    assert_predicate parse("-h"), :help?
    refute_predicate parse("-h"), :long_help?
    assert_predicate parse("--help"), :long_help?
    assert_predicate parse("-h", "--help"), :long_help?
    assert_predicate parse("--help", "-h"), :long_help?
    refute_predicate parse("x.rb"), :help?
  end

  # An unknown item or option only warns, and the program still runs. As in
  # ruby, "with-" and "without-" keep their "-", so they name no option.
  def test_an_unknown_dump_item_or_option_warns
    only = "zr: warning: but only [version, copyright, usage, help, yydebug, syntax, parsetree, insns]."

    assert_equal ["zr: warning: don't know how to dump 'parsetree-x',", only], parse("--dump=parsetree-x", "x.rb").warnings
    assert_equal ["zr: warning: don't know how to dump with 'bogus'"], parse("--dump=syntax+bogus", "x.rb").warnings
    assert_equal ["zr: warning: don't know how to dump without 'bogus'"], parse("--dump=-bogus", "x.rb").warnings
    assert_equal ["zr: warning: don't know how to dump with '-comment'"], parse("--dump=p+with-comment", "x.rb").warnings
    assert_equal ["zr: warning: don't know how to dump without '-comment'"], parse("--dump=p+without-comment", "x.rb").warnings
    assert_empty parse("--dump=p+comment+-optimize+error-tolerant", "--dump=-comment", "x.rb").warnings
    assert_empty parse("--dump=parsetree-x", "x.rb").dumps
  end

  def test_dump_needs_an_item
    error = assert_raises(RubyOptions::Invalid) { parse("--dump=", "-e", "1") }
    assert_equal "missing argument for --dump", error.message
  end

  def test_an_empty_script_name_is_standard_input
    assert_equal "-", parse("").script
    assert_equal "-", parse("-w", "", "a").script
    assert_equal ["a"], parse("", "a").args
  end

  def test_a_dos_line_end_after_a_switch_switches_nothing
    assert_equal ["1"], parse("-\r", "-e", "1").inline
  end

  def test_x_reads_no_script_from_e_code
    assert_equal "e", parse("-x", "-e", "1").switches.command_line
    assert_equal "x", parse("-x", "x.rb").switches.command_line
  end

  def test_a_program_runs_unless_only_the_version_is_asked
    assert parse("-e", "1").runs?(true)
    refute parse("-v").runs?(false)
    refute parse("--version", "x.rb").runs?(false)
    assert parse("-w").runs?(false)
    refute parse("-w").runs?(true)
  end
end

# Which first words make `zr` a ruby (`CLI.ruby_mode?`), and which name
# its commands.
class RubyModeDispatchTest < Minitest::Test
  CLI = Zr::CLI

  def test_a_command_word_wins_and_anything_else_is_a_ruby_program
    Dir.mktmpdir("zr-dispatch-") do |dir|
      script = File.join(dir, "script")
      File.write(script, "p 1\n")

      assert_equal [false, false, false, false, false],
                   [%w[run a.rb], %w[build], %w[compile x.rb], %w[-h], %w[--version]].map { |argv| CLI.ruby_mode?(argv, tty: true) }
      assert_equal [true, true, true, true, true, true],
                   [%w[app.rb], %w[-e 1], %w[-], %w[-- build], [script], %w[-w]].map { |argv| CLI.ruby_mode?(argv, tty: true) }
      refute CLI.ruby_mode?(%w[biuld], tty: true)
      assert CLI.ruby_mode?(%w[does_not_exist], tty: true)
      assert CLI.ruby_mode?(%w[script_name arg], tty: true)
      assert CLI.ruby_mode?(%w[/no/such/script], tty: true)
      assert CLI.ruby_mode?([""], tty: true)
      assert CLI.ruby_mode?(%w[sub/missing], tty: true)
    end
  end

  def test_with_no_words_zr_reads_standard_input_unless_it_is_a_terminal
    assert CLI.ruby_mode?([], tty: false)
    refute CLI.ruby_mode?([], tty: true)
  end

  def test_compile_is_another_name_for_build
    out, = capture_io do
      assert_raises(SystemExit) { CLI.start(%w[compile --help]) }
    end

    assert_equal CLI::Help::PAGES.fetch("build"), out
  end

  def test_only_a_program_that_the_same_words_give_again_tunes
    assert CLI.compiles?(%w[build x.rb -o x])
    assert CLI.compiles?(%w[-e 1])
    refute CLI.compiles?(%w[-C dir -e 1])
    refute CLI.compiles?(%w[-c -e 1])
    refute CLI.compiles?(%w[help])
  end

  def test_a_bundle_export_tunes_at_once_and_no_other_cache_command_tunes
    assert CLI.exports?(%w[cache export --target wasm32-wasi -o b.zrr])
    refute CLI.exports?(%w[cache clean --days 1])
    refute CLI.compiles?(%w[cache export])
  end

  def test_a_switch_that_ruby_rejects_ends_as_ruby_ends
    _, err = capture_io do
      error = assert_raises(SystemExit) { CLI.start(%w[--frob]) }
      assert_equal 1, error.status
    end

    assert_equal "zr: invalid option --frob  (-h will show valid options) (RuntimeError)\n", err
  end
end
