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

  def parse(*argv) = RubyOptions.parse(argv)

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

  def test_the_prelude_sets_what_each_switch_sets_in_rubys_order
    prelude = parse("-W0", "-d", "-I/l", "-rjson", "-l", "-s", "-Eascii-8bit:utf-8", "s.rb").prelude.to_s.lines(chomp: true)

    assert_equal ["$VERBOSE = true", "$DEBUG = true"], prelude.first(2)
    assert_includes prelude, '$LOAD_PATH.unshift("/l")'
    assert_includes prelude, '$\\ = "\n"'
    assert_operator prelude.index('require "json"'), :<, prelude.index('Encoding.default_external = "ASCII-8BIT"')
    assert_includes prelude, 'Encoding.default_internal = "UTF-8"'
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
    { "-0" => '$/ = "\x00".b', "-00" => '$/ = ""', "-0777" => "$/ = nil", "-012" => '$/ = "\n".b' }.each do |switch, line|
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
      %w[--encoding] => "missing argument for --encoding"
    }.each do |argv, message|
      error = assert_raises(RubyOptions::Invalid, argv.inspect) { parse(*argv) }
      assert_equal message, error.message
    end
  end

  def test_what_zr_cannot_do_is_refused_and_what_changes_nothing_is_taken
    assert_equal "--dump is not supported", parse("--dump=insns", "x.rb").refused
    assert_nil parse("-y", "--jit", "--yjit-call-threshold=1", "--crash-report=x", "--parser=prism", "x.rb").refused
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
    "bad.rb" => "def x\n  p (\nend\n"
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

  def test_load_path_and_required_libraries
    same_as_ruby("-Ilib", "-rfoo", "-e", "p Foo, $LOADED_FEATURES.grep(/foo/).size, $LOAD_PATH.include?(File.expand_path('lib'))")
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
  end

  def test_syntax_check_and_syntax_errors
    same_as_ruby("-c", "-e", "p 1")
    same_as_ruby("-c", "bad.rb")
    same_as_ruby("-e", "p (")
  end

  def test_errors_before_the_program_runs
    same_as_ruby("nope.rb")
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
  def same_as_ruby(*argv, stdin: "")
    in_dir do |dir|
      ruby = Open3.capture3(ENV_OF_BOTH, RbConfig.ruby, *argv, stdin_data: stdin, chdir: dir)
      zr = Open3.capture3(ENV_OF_BOTH, EXE, *argv, stdin_data: stdin, chdir: dir)
      expected = [ruby[0], ruby[1].gsub(/^#{Regexp.escape(RbConfig.ruby)}:|^ruby:/, "zr:"), ruby[2].exitstatus]

      assert_equal expected, [zr[0], zr[1], zr[2].exitstatus], argv.inspect
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
