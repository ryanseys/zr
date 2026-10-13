# frozen_string_literal: true

require "test_helper"
require "open3"
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
    assert_empty parse("--disable-jit", "--yjit", "x.rb").warnings
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

  def test_zrs_own_flags_go_to_zr
    assert_equal %w[--trace --gem csv=3.3.6], parse("--trace", "--gem", "csv=3.3.6", "x.rb").zr
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
    assert_predicate parse("--dump=h"), :help?
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

  def test_a_switch_that_ruby_rejects_ends_as_ruby_ends
    _, err = capture_io do
      error = assert_raises(SystemExit) { CLI.start(%w[--frob]) }
      assert_equal 1, error.status
    end

    assert_equal "zr: invalid option --frob  (-h will show valid options) (RuntimeError)\n", err
  end
end

# `zr` with ruby's switches, against ruby with the same words: the same
# output, errors and status. Each case builds a program (the run cache
# keeps it). Where ruby names itself, zr names itself.
class RubyModeTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  # The environment of both: no bundler and no collector limits of the
  # test run, which ruby would load or warn about.
  ENV_OF_BOTH = { "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil, "BUNDLER_SETUP" => nil,
                  "BUNDLER_VERSION" => nil, "BUNDLE_LOCKFILE" => nil }.merge(Zr::GcTuning::GC_ENV.transform_values { nil }).freeze

  FILES = {
    "in.txt" => "a b\nc d\n",
    "x.rb" => "p [:x, $VERBOSE, ARGV]\n",
    "sh.rb" => "#!/usr/bin/env ruby -w\np $VERBOSE\n",
    "s.rb" => "p [$x, $foo, $a_b, ARGV]\n",
    "xs.txt" => "garbage\n#!ruby -l\np __LINE__\nputs 'hi'\n",
    "sub/y.rb" => "p Dir.pwd.end_with?('sub')\n",
    "lib/foo.rb" => "module Foo; end\n",
    "bad.rb" => "def x\n  p (\nend\n",
    "handler.rb" => "at_exit { puts 'handler ran' }\n",
    "unparsed.rb" => "x = 1\nif true\n  1 +\n",
    "frozen.rb" => "# frozen_string_literal: true\ns = 'abc'\nbegin; s << 'x'; rescue => e; p e.message; end\n" \
                   "t = [\n  'lit']\nbegin; t[0].upcase!; rescue => e; p e.message; end\n",
    "chilled.rb" => "s = 'c'\ns << 'x'\np s\n",
    "detail.rb" => "class SyntaxError\n  def detailed_message(**)\n    Thread.new {}.join\n" \
                   "    \"<\#{super}>\n<\#{File.basename(__FILE__)}>\"\n  end\nend\n",
    "showpath.rb" => "class SyntaxError\n  def detailed_message(**) = \"path=\#{path}\n\#{super}\"\nend\n",
    "hybrid.sh" => "#!/usr/bin/env bash\necho error && exit 1\n#!ruby\nputs 'success'\n",
    "bt.rb" => "def a = raise('oops')\ndef b = a\ndef c = b\ndef d = c\nbegin\n  d\nrescue => e\n  puts e.full_message(highlight: false)\nend\nd\n"
  }.freeze

  def test_e_code_runs_as_the_file_dash_e
    same_as_ruby("-e", "p [$0, __FILE__, __LINE__, __dir__, defined?(DATA)]", "-e", "p ARGV", "--", "-x", "y")
  end

  def test_a_script_and_its_arguments
    same_as_ruby("x.rb", "a", "-b")
    same_as_ruby("--", "x.rb", "q")
  end

  def test_standard_input_is_the_program_without_a_script
    same_as_ruby(stdin: "p [$0, __FILE__, DATA.read]\n__END__\nhi\n")
    same_as_ruby("-", "a", stdin: "p ARGV\n")
  end

  # A program's `RbConfig.ruby` is the zr that ran it, as a ruby
  # program's is its ruby.
  def test_rbconfig_ruby_runs_the_interpreter_that_ran_the_program
    same_as_ruby("-e", 'system(RbConfig.ruby, "-e", "print 6 * 7; exit 7"); p $?.exitstatus')
  end

  def test_the_loop_switches_read_their_input_as_ruby
    same_as_ruby("-lane", "print $F.reverse.join(' ')", "in.txt")
    same_as_ruby("-pe", "$_.upcase!", "in.txt")
    same_as_ruby("-n", "-e", "BEGIN { p :b }; END { p :e }; print if /c/", "in.txt")
    same_as_ruby("-F:", "-ane", "p $F, [$-a, $-l, $-p]", stdin: "a:b\n")
  end

  def test_a_program_that_kills_itself_dies_of_the_signal
    in_dir do |dir|
      _, err, status = Open3.capture3(ENV_OF_BOTH, EXE, "-e", "Process.kill(:KILL, $$); sleep 1", chdir: dir)

      assert_equal ["", Signal.list["KILL"]], [err, status.termsig]
    end
  end

  def test_the_loop_switches_define_chomp_chop_sub_and_gsub_on_the_last_line
    same_as_ruby("-n", "-e", "chomp; chop; sub(/b/, 'X'); gsub(/c/) { 'Y' }; p $_", stdin: "abc1\nbcd2\n")
    same_as_ruby("-n", "-e", "p Kernel.private_method_defined?(:chomp)", stdin: "\n")
    same_as_ruby("-n", "-e", "Kernel.chomp; Kernel.chop; p $_", stdin: "abc\n")
    same_as_ruby("-e", "p Kernel.private_method_defined?(:chomp)")
  end

  def test_parse_warnings_follow_verbose_and_go_through_warning_warn
    same_as_ruby("-W0", "-e", "{a: 1, a: 2}")
    same_as_ruby("-e", "{a: 1, a: 2}")
    same_as_ruby("-w", "-e", "eval(%q(defined?(x); 1))")
    same_as_ruby("-e", "def Warning.warn(m) = print(%q(caught: ), m); eval(%q({b: 1, b: 2}))")
  end

  def test_warning_switches_set_verbose_and_the_categories
    same_as_ruby("-w", "x.rb")
    same_as_ruby("-W0", "-e", "p $VERBOSE; warn 'shown'")
    same_as_ruby("-W:no-deprecated", "-e", "p [Warning[:deprecated], Warning[:experimental], $VERBOSE]")
    same_as_ruby("-w", "-e", "x = 1")
    same_as_ruby("sh.rb")
  end

  def test_include_directories_split_and_expand_as_ruby
    same_as_ruby("-I", "./\u3042:./b:c", "-e", "p $LOAD_PATH.first(3).map { _1.sub(Dir.pwd, %(PWD)) }")
  end

  def test_load_path_and_required_libraries
    same_as_ruby("-Ilib", "-rfoo", "-e", "p Foo, $LOADED_FEATURES.grep(/foo/).size, $LOAD_PATH.include?(File.expand_path('lib'))")
  end

  # -rrubygems is the gem prelude's own load, not a second one that its
  # Gem autoload would start while rubygems.rb loads.
  def test_requiring_rubygems_with_r
    same_as_ruby("-rrubygems", "-e", "p Gem::VERSION.is_a?(String), $LOADED_FEATURES.grep(/rubygems.rb\\z/).size")
    same_as_ruby("-rrubygems", "-e", "p 1")
  end

  def test_s_x_and_c_dir
    same_as_ruby("-s", "s.rb", "-x", "-foo=bar", "-a-b", "z")
    same_as_ruby("-s", "s.rb", "-a.b")
    same_as_ruby("-x", "xs.txt")
    same_as_ruby("-x", "in.txt")
    same_as_ruby("-C", "sub", "y.rb")
  end

  def test_separators_and_encodings
    same_as_ruby("-l", "-00", "-e", "p [$/, $\\]")
    same_as_ruby("-E", "ISO-8859-1:UTF-8", "-e", "p [Encoding.default_external, Encoding.default_internal]")
    same_as_ruby("--disable-gems", "--enable=frozen-string-literal", "-e", "p defined?(Gem), 'a'.frozen?")
    same_as_ruby("-072", "-e", "p $/, $/.frozen?, $-0.frozen?")
    same_as_ruby("-Ke", "-e", "p [__ENCODING__, Encoding.default_external, Encoding.default_internal]")
    same_as_ruby("-U", "-KS", "-e", "p [__ENCODING__, Encoding.default_internal]")
    same_as_ruby("-U", "-E:ascii", "-e", "1")
    same_as_ruby("-wKe", "-e", "p __ENCODING__.name")
    same_as_ruby("-W0", "-e", "p $-W")
    same_as_ruby("-W1", "-e", "p $-W")
    same_as_ruby("-W", "-e", "p $-W")
    same_as_ruby("-e", "p $-W, defined?($-W)")
    same_as_ruby("-Wx", "-e", "p $-W")
    # An internal encoding that a switch sets gives the standard streams
    # the default encodings, and a write converts to the external one.
    streams = "p [$stdin, $stdout, $stderr].map { [_1.external_encoding, _1.internal_encoding] }"
    ["-E:utf-8", "-Eeuc-jp:utf-8", "-U", "-Eutf-8"].each { |switch| same_as_ruby(switch, "-e", streams) }
    same_as_ruby("-Eutf-8:cp932", "-e",
                 'puts "\x82\xa0".dup.force_encoding("cp932"); $stderr = $stdout; raise "\x82\xa0".dup.force_encoding("cp932")')
    same_as_ruby("-e", "Encoding.default_internal = 'utf-8'; #{streams}")
    # -E sets the encodings with no warning, even when -w or -v asks for them.
    same_as_ruby("-w", "-Eutf-8:Windows-31J", "-e", "p [Encoding.default_external, Encoding.default_internal]")
    same_as_ruby("-W2", "-U", "-e", "p Encoding.default_internal")
    same_as_ruby("-w", "-e", "Encoding.default_internal = 'EUC-JP'; p Encoding.default_internal")
  end

  def test_a_launcher_script_and_the_backtrace_limit
    same_as_ruby("hybrid.sh")
    same_as_ruby("--backtrace-limit=1", "bt.rb")
    same_as_ruby("--disable=did_you_mean", "--backtrace-limit=0", "-e", "p defined?(DidYouMean), Thread::Backtrace.limit")
  end

  def test_syntax_check_and_syntax_errors
    same_as_ruby("-c", "-e", "p 1")
    same_as_ruby("-c", "bad.rb")
    same_as_ruby("-e", "p (")
    # The -r libraries load before the report, and their exit handlers run.
    same_as_ruby("-r./handler.rb", "-e", "{")
    # The report goes through SyntaxError#detailed_message, which a library
    # may redefine, and the error has the script's path.
    same_as_ruby("-r./detail.rb", "unparsed.rb")
    same_as_ruby("-r./showpath.rb", "unparsed.rb")
    same_as_ruby("-r./detail.rb", "-", stdin: "1+\n")
    # The parse warns at the program's level, before the report.
    same_as_ruby("-w", "unparsed.rb")
    same_as_ruby("-W0", "unparsed.rb")
    same_as_ruby("--disable-gems", "unparsed.rb")
  end

  # -y and --dump print in place of the run; prism's tree prints as ruby's
  # C printer prints it.
  def test_dump_prints_the_syntax_check_and_the_tree
    same_as_ruby("-y", "-e", "p 1")
    same_as_ruby("--dump=syntax,parsetree", "x.rb")
    same_as_ruby("--disable-gems", "--dump=parsetree", "-e", "%I[foo bar]")
    same_as_ruby("--dump", "p", "-e", "def m(a, *b, k: 1, **o, &blk) = yield\nm(1) { |q| \"\\x01\#{q}\" }; x = -2**64; 1e400")
    same_as_ruby("--dump=parsetree", "bad.rb")
    same_as_ruby("--dump=syntax", "missing.rb")
    same_as_ruby("--dump=foo,-bar,syntax+baz", "-e", "p 1")
    same_as_ruby("--dump=foo", "x.rb")
    same_as_ruby("--dump=copyright,syntax", "-e", "p 1")
  end

  # --debug=frozen-string-literal: a literal keeps where it was made, which
  # a FrozenError and the chilled String's warning name.
  def test_debug_frozen_string_literal_names_where_a_string_was_made
    same_as_ruby("--debug=frozen-string-literal", "frozen.rb")
    same_as_ruby("--debug-frozen-string-literal", "frozen.rb")
    same_as_ruby("frozen.rb")
    same_as_ruby("-W:deprecated", "--debug=frozen-string-literal", "chilled.rb")
    same_as_ruby("-W:deprecated", "chilled.rb")
    same_as_ruby("--debug=frozen-string-literal", "-e", "p $DEBUG")
    # -d and --debug turn every debug feature on, this one too.
    same_as_ruby("--disable-gems", "-d", "frozen.rb")
    same_as_ruby("--disable-gems", "--debug", "frozen.rb")
    same_as_ruby("--disable-gems", "--enable-frozen-string-literal", "--debug", "-e", "'foo' << 'bar'")
  end

  # -S looks in RUBYPATH, then PATH, as dln_find_1 does: "~" is HOME, an
  # empty entry is the current directory, and a path too long for the
  # buffer is skipped, with a warning under -w.
  def test_s_searches_rubypath_then_path
    same_as_ruby("-S", "x.rb", env: { "RUBYPATH" => "~", "HOME" => "DIR" })
    same_as_ruby("-S", "y.rb", env: { "RUBYPATH" => "/nope:~/sub", "HOME" => "DIR" })
    same_as_ruby("-S", "x.rb", env: { "RUBYPATH" => ":/nope" })
    same_as_ruby("-S", "sub/y.rb", env: { "RUBYPATH" => "DIR" })
    same_as_ruby("-S", "-w", "nothing_here", env: { "RUBYPATH" => "~", "HOME" => "/foo" * 1024 })
    same_as_ruby("-S", "-w", "nothing_here", env: { "RUBYPATH" => "~#{"/foo" * 1024}", "HOME" => "/foo" })
    same_as_ruby("-S", "nothing_here", env: { "RUBYPATH" => "~", "HOME" => "/foo" * 1024 })
  end

  # --debug names ruby's debug features, by prefix and in any case; an
  # unknown name warns, and --debug- alone is no option.
  def test_debug_switch_names
    same_as_ruby("--debug=frozen", "-e", "p $DEBUG")
    same_as_ruby("--debug=FROZEN-STRING-LITERAL,bar", "-e", "p $DEBUG")
    same_as_ruby("--debug-foo", "-e", "p $DEBUG")
    same_as_ruby("--debug-", "-e", "p $DEBUG")
    same_as_ruby("--disable-gems", "--debug=", "-e", "p $DEBUG")
  end

  # The backtrace limit is a long; a larger one is refused.
  def test_backtrace_limit_takes_a_long
    same_as_ruby("--backtrace-limit=9223372036854775807", "-e", "p Thread::Backtrace.limit")
    same_as_ruby("--backtrace-limit=9223372036854775808", "-e", "p Thread::Backtrace.limit")
    same_as_ruby("--backtrace-limit=4611686018427387904", "-e", "p Thread::Backtrace.limit; raise 'x'")
  end

  # The command line's warning level wins over RUBYOPT's.
  def test_the_command_line_level_wins_over_rubyopt
    same_as_ruby("-W1", "-e", "p $VERBOSE", env: { "RUBYOPT" => "-w" })
    same_as_ruby("-W0", "-e", "p $VERBOSE", env: { "RUBYOPT" => "-w" })
    same_as_ruby("-w", "-e", "p $VERBOSE", env: { "RUBYOPT" => "-W0" })
    same_as_ruby("-e", "p $VERBOSE", env: { "RUBYOPT" => "-w" })
  end

  # A shebang line that ends with "\r\n" warns, once, unless -W0.
  def test_a_shebang_line_with_a_carriage_return_warns
    same_as_ruby(stdin: "#!ruby -KU -Eutf-8\r\np \"あ\"\r\n")
    same_as_ruby("-W0", stdin: "#!ruby\r\np 1\r\n")
    same_as_ruby("-w", stdin: "#!ruby\r\np 1\r\n")
    same_as_ruby("-x", stdin: "junk\n#!ruby -w\r\np 2\r\n")
  end

  # A first line of `#!` alone is a comment; with anything after it that
  # does not name ruby, it is a launcher, and the script runs from the
  # first `#!ruby` line (test_rubyoptions.rb's test_shebang).
  def test_a_bare_shebang_line_is_a_comment
    same_as_ruby(stdin: "#!")
    same_as_ruby("-c", stdin: "#!")
    same_as_ruby(stdin: "#!\np 1\n")
    same_as_ruby(stdin: "#! \np 1\n")
    same_as_ruby(stdin: "#!\r\np 1\n")
  end

  # Without gems, the libraries of ruby's gem prelude are not there.
  def test_no_gems_means_no_gem_prelude_libraries
    code = "p [defined?(ErrorHighlight), defined?(SyntaxSuggest), defined?(DidYouMean), defined?(Gem)]; foo rescue p $!.message"
    same_as_ruby("--disable=gems", "-e", code)
    same_as_ruby("--disable-did_you_mean", "-e", code)
    same_as_ruby("--disable-error_highlight", "-e", code)
    same_as_ruby("--disable=syntax_suggest", "-e", code)
    same_as_ruby("--disable=gems", "-e", "nil.foo")
    # The first error display loads only the libraries that are still on.
    same_as_ruby("--disable=error_highlight", "-e", "[1].frist")
    same_as_ruby("--disable=did_you_mean", "-e", "[1].frist")
  end

  # ruby 4.1 makes the libraries autoloads; the first error display loads them.
  def test_the_message_decorators_load_at_the_first_error_display
    same_as_ruby("-e", "p Object.autoload?(:DidYouMean); [1].frist rescue p $!.detailed_message; p Object.autoload?(:DidYouMean)")
    same_as_ruby("-e", "[1].frist")
  end

  def test_errors_before_the_program_runs
    same_as_ruby("nope.rb")
    same_as_ruby("no/such/script")
    same_as_ruby("", "a", stdin: "p ARGV, $0")
    # A first line that runs another interpreter makes the script run as
    # with -x, from standard input too.
    same_as_ruby(stdin: "#! /bin/not_the_interpreter\r\np 1\r\n")
    same_as_ruby(stdin: "#! /bin/not_the_interpreter\np 1\n#!ruby\np 2\n")
    same_as_ruby("--disable-gems", "-e", "begin; require 'no_such_feature_zr'; rescue LoadError => e; p e.message; end")
    # The platform is the build host's, which zr's target need not match.
    same_as_ruby("-v", "-e", "p 1", platform: true)
    same_as_ruby("-q")
    same_as_ruby("-C", "nodir", "-e", "1")
    same_as_ruby("-e", "exit 7")
  end

  def test_in_place_editing_writes_each_file_and_keeps_a_backup
    in_dir do |dir|
      File.write(File.join(dir, "f.txt"), "a\nb\n")
      out, err, status = Open3.capture3(ENV_OF_BOTH, EXE, "-i.bak", "-pe", "$_.upcase!", "f.txt", chdir: dir)

      assert_equal ["", "", 0], [out, err, status.exitstatus]
      assert_equal ["A\nB\n", "a\nb\n"], %w[f.txt f.txt.bak].map { |name| File.read(File.join(dir, name)) }
    end
  end

  private

  # Runs `argv` under ruby and under zr in a directory with FILES, and
  # checks that both give the same output, errors and status.
  #: (*String argv, ?stdin: String) -> void
  # `env` is more of the environment, where "DIR" stands for the
  # directory that both run in. `platform` masks the " [platform]" that
  # ends a line of the output, as in RUBY_DESCRIPTION.
  def same_as_ruby(*argv, stdin: "", env: {}, platform: false)
    in_dir do |dir|
      given = ENV_OF_BOTH.merge(env.transform_values { |value| value.gsub("DIR", dir) })
      ruby = Open3.capture3(given, RbConfig.ruby, *argv, stdin_data: stdin, chdir: dir)
      zr = Open3.capture3(given, EXE, *argv, stdin_data: stdin, chdir: dir)
      expected = [ruby[0], ruby[1].gsub(/^#{Regexp.escape(RbConfig.ruby)}:|^ruby:/, "zr:"), ruby[2].exitstatus]
      actual = [zr[0], zr[1], zr[2].exitstatus]
      expected[0], actual[0] = [expected[0], actual[0]].map { |out| out.sub(/ \[[\w.-]+\]$/, " [platform]") } if platform

      assert_equal expected, actual, argv.inspect
    end
  end

  #: () { (String) -> void } -> void
  def in_dir
    Dir.mktmpdir("zr-ruby-mode-") do |dir|
      dir = File.realpath(dir)
      FILES.each do |name, text|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
      end
      yield dir
    end
  end
end
