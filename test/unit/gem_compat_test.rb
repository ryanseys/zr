# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../../tool/lib/zr/dev/gems"
require_relative "../../tool/gems"
require_relative "../../tool/gems/sweep"

# Tests the parts of `zr-dev gems` (tool/lib/zr/dev/gems/) on a corpus of
# tiny gems in test/fixtures/gems. No test uses the network, builds a
# program or runs ruby: the resolver is offline, and a fake runner
# answers for zr and for ruby.
class GemCompatTest < Minitest::Test
  Gems = Zr::Dev::Gems
  FIXTURES = File.expand_path("../fixtures/gems", __dir__)
  CORPUS = Gems::Corpus.new(File.join(FIXTURES, "corpus"))
  OVERRIDES = File.join(FIXTURES, "overrides")

  def setup
    @dir = Dir.mktmpdir("zr-gem-compat-")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Request

  def test_a_request_is_a_name_a_version_or_a_path
    assert_equal ["rack", nil, nil], Gems::Request.parse("rack").to_h.values
    assert_equal ["rack", "3.1.8", nil], Gems::Request.parse("rack=3.1.8").to_h.values
    assert_equal File.expand_path("src/rack"), Gems::Request.parse("./src/rack").path
    assert Gems::Request.parse("rack=3.1.8").requirement.satisfied_by?(Gem::Version.new("3.1.8"))
    refute Gems::Request.parse("rack=3.1.8").requirement.satisfied_by?(Gem::Version.new("3.1.9"))
  end

  def test_a_bad_request_names_the_forms
    error = assert_raises(ArgumentError) { Gems::Request.parse("rack=latest") }
    assert_includes error.message, "NAME=VERSION"
  end

  # rubygems.org has gems whose names start with a dot or an underscore.
  # A name of dots alone would name a directory above another.
  def test_a_request_takes_every_name_that_rubygems_takes_but_dots_alone
    assert_equal %w[.cat _x a.b], %w[.cat _x a.b].map { Gems::Request.parse(_1).name }
    %w[. ..].each { |name| assert_raises(ArgumentError) { Gems::Request.parse(name) } }
  end

  def test_a_sweep_skips_a_name_of_the_top_list_that_it_cannot_take
    top = File.join(@dir, "top.tsv")
    Gems::Top.write({ "rack" => 3, ".." => 2, "cexty" => 1 }, top)
    sweep = Zr::Dev::Commands::Gems::Sweep.new("gems sweep")
    sweep.instance_variable_set(:@top, Zr::Dev::Commands::Gems::Sweep.ranks("3"))
    sweep.define_singleton_method(:top_list) { Gems::Top.read(top) }

    words, _ = nil
    _, err = capture_io { words = sweep.words(["tiny"]) }

    assert_equal %w[tiny rack cexty], words
    assert_includes err, %(skipped ".." of log/gems/top.tsv)
  end

  # Corpus

  def test_the_corpus_reads_the_markers_and_the_gemspec
    tiny = CORPUS.find("tiny")

    assert_equal ["tiny", "1.0.0", "corpus", ["lib"], []], [tiny.name, tiny.version, tiny.source, tiny.require_paths, tiny.extensions]
    assert_equal [["helper", ">= 1.1"], ["json", ">= 2"]], tiny.dependencies
    assert_equal "1.2.0", CORPUS.find("helper").version
    assert_equal ["ext/cexty/extconf.rb"], CORPUS.find("cexty").extensions
  end

  # A corpus written before the markers' rename gives them their names.
  def test_the_corpus_renames_a_marker_of_its_former_name
    dir = File.join(@dir, "old")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, ".zeo-probe-version"), "3.1.4")
    File.write(File.join(dir, ".zeo-probe-spec"), '{"require_paths":["lib"]}')

    assert_equal "3.1.4", Zr::Dev::Gems::Corpus.new(@dir).find("old").version
    assert_equal %w[.zr-corpus-spec .zr-corpus-version lib], Dir.children(dir).sort
  end

  def test_the_corpus_finds_a_gem_only_by_its_exact_path
    assert_nil CORPUS.find("tin")
  end

  def test_a_directory_named_name_version_gives_the_version
    dir = File.join(@dir, "plain-2.5.0")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    subject = Gems::Corpus.read(dir, source: "path")

    assert_equal ["plain", "2.5.0", ["lib"]], [subject.name, subject.version, subject.require_paths]
  end

  def test_a_directory_without_a_version_is_not_found
    dir = File.join(@dir, "unversioned")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    error = assert_raises(Gems::Failure) { Gems::Corpus.read(dir, source: "path") }
    assert_equal "not-found", error.kind
  end

  # Resolver

  def test_a_dependency_comes_from_the_corpus_and_zr_has_json
    subject, deps = resolver.resolve(Gems::Request.parse("tiny"))

    assert_equal "tiny 1.0.0", subject.to_s
    assert_equal ["helper 1.2.0"], deps.map(&:to_s), "zr's json 3.0.2 port satisfies json >= 2"
  end

  def test_a_dependency_that_nothing_satisfies_fails_to_resolve
    dir = File.join(@dir, "needy")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "needy.gemspec"), <<~RUBY)
      Gem::Specification.new do |s|
        s.name = "needy"
        s.version = "1.0.0"
        s.summary = "needs a helper that no one has"
        s.authors = ["zr"]
        s.add_dependency "helper", ">= 9"
      end
    RUBY
    error = assert_raises(Gems::Failure) { resolver.resolve(Gems::Request.parse(dir)) }

    assert_equal "resolve", error.kind
    assert_includes error.message, "helper"
  end

  # A resolver that fails with a NoMethodError, as a bug of RubyGems
  # would, while it makes the error of another failure.
  class BrokenResolver
    def initialize(cause) = @cause = cause

    def resolve
      raise @cause
    rescue StandardError
      nil.request
    end
  end

  def test_a_no_method_error_of_the_resolver_is_not_a_conflict
    assert_raises(NoMethodError) { Gems::Resolver.requests(BrokenResolver.new(ArgumentError.new("x"))) }
  end

  def test_an_error_of_the_tool_on_one_gem_fails_that_gem_and_not_the_sweep
    resolver = Object.new
    def resolver.resolve(_request) = nil.fetch
    result = Gems::Trial.new(resolver: resolver, runner: Runner.new, overrides: OVERRIDES, logs: File.join(@dir, "logs"), c_scan: c_scan,
                             work: File.join(@dir, "work"), reference: Reference).call(Gems::Request.parse("tiny"))

    assert_equal [:fails, "tool-error"], [result.tier, result.kind]
    assert_match(/\ANoMethodError: undefined method 'fetch' for nil/, result.detail)
    assert_includes File.read(result.log), "gem_compat_test.rb", "the log keeps the backtrace"
  end

  def test_the_resolver_goes_past_zrs_version_when_another_gem_needs_an_older_one
    corpus = gem_dir("corpus/minitest", "5.25.0")
    gem_dir("corpus/old", "1.0.0", "minitest" => "< 6")
    root = gem_dir("root", "1.0.0", "minitest" => ">= 0", "old" => ">= 1")
    resolver = Gems::Resolver.new(store: Gems::FetchedGems.new(@dir), corpus: Gems::Corpus.new(File.dirname(corpus)), offline: true, remote: nil)
    _, deps = resolver.resolve(Gems::Request.parse(root))

    assert_equal ["minitest 5.25.0", "old 1.0.0"], deps.map(&:to_s).sort
  end

  # A version's `ruby` release wins over its precompiled ones, and a
  # version with none (sorbet-static's) takes the release for this
  # machine: universal-darwin on an arm64 Mac, not Linux's or Java's.
  def test_the_sets_keep_the_ruby_release_of_a_version_else_this_machines
    releases = { "1.0.0" => %w[arm64-darwin ruby], "2.0.0" => %w[aarch64-linux java universal-darwin x86_64-linux] }
    specs = releases.flat_map do |version, platforms|
      platforms.map do |platform|
        Gem::Specification.new do |s|
          s.name = "native"
          s.version = version
          s.platform = platform
        end
      end
    end
    set = Class.new(Gem::Resolver::Set) { define_method(:find_all) { |_| specs } }.new
    request = Gem::Resolver::DependencyRequest.new(Gem::Dependency.new("native"), nil)
    found = Gems::Resolver::Preferred.new([set, set]).find_all(request).map { |s| [s.version.to_s, s.platform.to_s] }

    skip "needs a darwin host" unless Gem::Platform.local.os == "darwin"
    assert_equal [%w[1.0.0 ruby], %w[2.0.0 universal-darwin]], found
  end

  def test_a_failure_to_resolve_keeps_the_gems_version
    root = gem_dir("root", "1.0.0", "helper" => ">= 9")
    trial_result = trial(Runner.new).call(Gems::Request.parse(root))

    assert_equal ["root", "1.0.0", :fails, "resolve"], [trial_result.name, trial_result.version, trial_result.tier, trial_result.kind]
  end

  def test_offline_a_gem_missing_from_the_corpus_and_the_store_is_not_found
    error = assert_raises(Gems::Failure) { resolver.resolve(Gems::Request.parse("absent")) }
    assert_equal "not-found", error.kind
  end

  def test_a_version_that_the_corpus_does_not_have_is_not_taken_from_it
    error = assert_raises(Gems::Failure) { resolver.resolve(Gems::Request.parse("tiny=2.0.0")) }
    assert_equal "not-found", error.kind
  end

  # FetchedGems

  def test_the_store_unpacks_a_gem_and_reads_it_back
    store = Gems::FetchedGems.new(@dir)
    subject = store.unpack(package("packed", "0.4.0", "lib/packed.rb" => "module Packed; end\n"))

    assert_equal ["packed", "0.4.0", "rubygems", File.join(store.gems, "packed-0.4.0")], [subject.name, subject.version, subject.source, subject.root]
    assert File.file?(File.join(subject.root, "lib/packed.rb"))
    assert_equal "packed", Gem::Specification.load(File.join(store.specifications, "packed-0.4.0.gemspec")).name, "zr build --gem reads this gemspec"
    assert_equal [subject], store.versions("packed")
    assert_equal subject, store.find("packed", "0.4.0")
    assert_equal subject, store.unpack(package("packed", "0.4.0", "lib/packed.rb" => "module Packed; end\n"))
  end

  def test_offline_the_resolver_takes_the_newest_version_in_the_store
    store = Gems::FetchedGems.new(@dir)
    store.unpack(package("packed", "0.4.0", "lib/packed.rb" => ""))
    store.unpack(package("packed", "0.10.0", "lib/packed.rb" => ""))

    assert_equal "0.10.0", Gems::Resolver.new(store: store, offline: true, remote: nil).find(Gems::Request.parse("packed")).version
  end

  # Rules

  # zr builds a gem with a C extension that it does not port, but for its
  # C part, so no rule refuses one before the build.
  def test_a_gem_with_a_c_extension_is_not_refused_before_the_build
    assert_nil Gems::Rules.refusal([CORPUS.find("tiny"), CORPUS.find("cexty")])
  end

  def test_a_port_outside_its_range_is_refused_and_inside_it_is_not
    json = CORPUS.find("json")

    assert_equal "port-range:json", Gems::Rules.refusal([json]).kind
    assert_nil Gems::Rules.refusal([json.with(version: Zr::Library::Ports::ALL["json"].version)])
  end

  # Override

  def test_an_override_skips_a_gem_or_names_its_requires
    assert_equal "needs a running server", Gems::Override.for("skipped", dir: OVERRIDES).skip
    parts = Gems::Override.for("multi-part", dir: OVERRIDES)
    assert_equal [nil, ["multi/part"], false], [parts.skip, parts.requires, parts.smoke?]
    assert_predicate Gems::Override.for("tiny", dir: OVERRIDES), :smoke?
    assert_nil Gems::Override.for("helper", dir: OVERRIDES)
  end

  # Trial

  def test_the_entry_is_the_name_the_name_as_a_path_or_the_only_file
    trial = trial(Runner.new)

    assert_equal "tiny", trial.entry(CORPUS.find("tiny"))
    assert_equal "multi/part", trial.entry(CORPUS.find("multi-part"))
    assert_equal "only", trial.entry(CORPUS.find("loner"))
  end

  def test_the_entry_can_be_the_name_with_underscores
    dir = gem_dir("activerecord", "8.1.4")
    File.write(File.join(dir, "lib/arel.rb"), "")
    File.write(File.join(dir, "lib/active_record.rb"), "")

    assert_equal "active_record", trial(Runner.new).entry(Gems::Corpus.read(dir, source: "path"))
  end

  # A gem whose files are all in a directory: the parts of its name spell
  # the file below it.
  def test_the_entry_can_be_spelled_by_the_parts_of_the_name
    dir = gem_dir("cucumber-tag-expressions", "6.1.0")
    FileUtils.mkdir_p(File.join(dir, "lib/cucumber/tag_expressions"))
    File.write(File.join(dir, "lib/cucumber/tag_expressions.rb"), "")
    File.write(File.join(dir, "lib/cucumber/tag_expressions/parser.rb"), "")
    net = gem_dir("gitlab-net-dns", "0.9.2")
    FileUtils.mkdir_p(File.join(net, "lib/net"))
    File.write(File.join(net, "lib/net/dns.rb"), "")

    assert_equal "cucumber/tag_expressions", trial(Runner.new).entry(Gems::Corpus.read(dir, source: "path"))
    assert_equal "net/dns", trial(Runner.new).entry(Gems::Corpus.read(net, source: "path"))
  end

  # From the whole name to its last part; the name and the name with each
  # `-` as `/` come first in `entry`, so they are not here.
  def test_the_spelled_names_go_from_the_whole_name_to_its_last_part
    assert_equal %w[a_b_c a/b_c b/c b_c c], Gems::Trial.spelled("a-b-c")
  end

  def test_a_gem_with_no_entry_fails
    dir = File.join(@dir, "empty-1.0.0")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    error = assert_raises(Gems::Failure) { trial(Runner.new).entry(Gems::Corpus.read(dir, source: "path")) }

    assert_equal "no-entry", error.kind
  end

  def test_the_probe_requires_each_feature
    probe = Gems::Trial.probe(%w[multi/part tiny])

    assert_includes probe, %(require "multi/part"\nrequire "tiny"\n)
    refute_includes probe, "REQUIRES"
  end

  def test_a_gem_whose_probe_gives_rubys_output_loads
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse("helper"))

    assert_equal [:loads, nil], [result.tier, result.kind]
    assert_equal %i[build ruby zr], runner.steps
    assert_includes runner.argvs.first, "helper=#{CORPUS.find("helper").root}"
    assert File.file?(result.log)
  end

  def test_ruby_loads_its_own_copy_of_a_gem_that_zr_ports
    dir = json_at("3.0.9")
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse(dir))

    assert_equal :loads, result.tier
    assert_includes runner.argvs[0], "json=#{dir}", "zr builds the gem's Ruby half with its port"
    refute_includes runner.argvs[1], File.join(dir, "lib"), "the unpacked gem has no compiled C for ruby"
  end

  def test_a_gem_at_the_version_that_zr_carries_is_no_override
    runner = Runner.new
    trial(runner).call(Gems::Request.parse(json_at(Zr::Library::Ports::ALL["json"].version)))

    refute_includes runner.argvs[0], "--gem"
  end

  def test_ruby_finds_each_gem_on_its_gem_path_too
    runner = Runner.new
    trial(runner).call(Gems::Request.parse("tiny"))

    assert_equal ["helper-1.2.0.gemspec", "tiny-1.0.0.gemspec", CORPUS.find("helper").root, CORPUS.find("tiny").root], runner.homes.first
  end

  def test_a_trial_that_runs_nothing_stops_after_the_build
    runner = Runner.new
    result = Gems::Trial.new(resolver: resolver, runner: runner, overrides: OVERRIDES, logs: File.join(@dir, "logs"), c_scan: c_scan,
                             work: File.join(@dir, "work"), reference: Reference, run: false).call(Gems::Request.parse("tiny"))

    assert_equal :builds, result.tier
    assert_equal [:build], runner.steps, "neither ruby nor the binary runs, and no smoke program"
    assert result.passed?(run: false)
    refute_predicate result, :passed?
  end

  def test_a_trial_that_runs_nothing_still_fails_a_build_that_fails
    runner = Runner.new(build: answer("", "zr: boom\n", 1))
    result = Gems::Trial.new(resolver: resolver, runner: runner, overrides: OVERRIDES, logs: File.join(@dir, "logs"), c_scan: c_scan,
                             work: File.join(@dir, "work"), reference: Reference, run: false).call(Gems::Request.parse("tiny"))

    assert_equal :fails, result.tier
    assert_equal [:build], runner.steps
  end

  def test_build_only_takes_no_path_and_no_corpus_whose_gemspec_would_run
    sweep = ->(*argv) { Zr::Dev::Commands::Gems::Sweep.new("gems sweep").start(["--build-only", *argv]) }

    _, err = capture_io { assert_raises(SystemExit) { sweep.call("./some/gem") } }
    assert_includes err, "--build-only takes no path"
    _, err = capture_io { assert_raises(SystemExit) { sweep.call("--corpus", FIXTURES, "tiny") } }
    assert_includes err, "--build-only takes no corpus"
  end

  def test_rubys_gem_path_holds_only_the_trials_gems_and_not_the_whole_store
    store = Gems::FetchedGems.new(@dir)
    packed = store.unpack(package("packed", "0.4.0", "lib/packed.rb" => ""))
    store.unpack(package("other", "1.0.0", "lib/other.rb" => ""))
    runner = Runner.new

    trial(runner).call(Gems::Request.parse("packed"))

    assert_equal ["packed-0.4.0.gemspec", packed.root], runner.homes.first,
                 "a gem of the store whose C extension was never built makes ruby warn"
  end

  def test_a_smoke_program_that_gives_rubys_output_verifies_the_gem
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse("tiny"))

    assert_equal :verified, result.tier
    assert_equal %i[build ruby zr build ruby zr], runner.steps
    assert_includes runner.argvs.first, "helper=#{CORPUS.find("helper").root}", "each dependency is a --gem"
  end

  def test_an_override_skips_a_gem_before_it_is_found
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse("skipped"))

    assert_equal [:skipped, "skip", "needs a running server"], [result.tier, result.kind, result.detail]
    assert_empty runner.steps
  end

  # `zr build`'s warning for a gem whose C part it does not port.
  NATIVE_WARNING = "zr: warning: cexty 1.0.0 (--gem cexty=/c) has a C extension, and zr has no port of it. zr compiles only Ruby: " \
                   "its Ruby files compile, and a require of its C part raises LoadError if it runs\n"

  def test_a_gem_whose_c_part_zr_does_not_port_builds_and_names_it
    runner = Runner.new(build: answer("", NATIVE_WARNING))
    result = Gems::Trial.new(resolver: resolver, runner: runner, overrides: OVERRIDES, logs: File.join(@dir, "logs"), c_scan: c_scan,
                             work: File.join(@dir, "work"), reference: Reference, run: false).call(Gems::Request.parse("cexty"))

    assert_equal [:builds, "cext:cexty"], [result.tier, result.kind]
    assert_equal [:build], runner.steps
  end

  def test_a_gem_whose_c_part_zr_does_not_port_loads_when_its_output_is_rubys
    result = trial(Runner.new(build: answer("", NATIVE_WARNING))).call(Gems::Request.parse("cexty"))

    assert_equal [:loads, nil], [result.tier, result.kind]
  end

  def test_a_gem_whose_c_part_zr_does_not_port_compiles_when_its_output_differs
    runner = Runner.new(build: answer("", NATIVE_WARNING), zr: answer("", "LoadError\n", 1))
    result = trial(runner).call(Gems::Request.parse("cexty"))

    assert_equal [:compiles, "cext:cexty"], [result.tier, result.kind]
  end

  def test_a_gem_whose_c_part_ruby_lacks_too_builds
    runner = Runner.new(build: answer("", NATIVE_WARNING), ruby: answer("", "LoadError\n", 1))
    result = trial(runner).call(Gems::Request.parse("cexty"))

    assert_equal [:builds, "cext:cexty"], [result.tier, result.kind]
    assert_equal %i[build ruby], runner.steps
  end

  def test_a_refusal_of_a_form_names_the_form
    runner = Runner.new(build: answer("", "zr: lib/loner.rb:3: zr does not support the flip-flop operator yet\n", 3))
    result = trial(runner).call(Gems::Request.parse("loner"))

    assert_equal [:refused, "refused:the flip-flop operator"], [result.tier, result.kind]
    assert_equal "lib/loner.rb:3: zr does not support the flip-flop operator yet", result.detail
  end

  def test_a_require_that_resolves_nowhere_names_the_feature
    err = "zr: lib/only.rb:1: cannot load such file -- rainbow/ext. Add it to the Gemfile\n"
    result = trial(Runner.new(build: answer("", err, 1))).call(Gems::Request.parse("loner"))

    assert_equal [:fails, "missing-require:rainbow/ext"], [result.tier, result.kind]
  end

  def test_other_output_from_the_binary_compiles_with_the_first_difference
    result = trial(Runner.new(zr: answer("Only Module\n  X\n"))).call(Gems::Request.parse("loner"))

    assert_equal [:compiles, "output-diff"], [result.tier, result.kind]
    assert_equal 'stdout line 2: ruby "  ", zr "  X"', result.detail
    assert_includes File.read(result.log), "--- stdout (ruby, then zr)"
  end

  def test_a_signal_in_the_binary_is_a_crash
    result = trial(Runner.new(zr: Zr::Diff::Answer.new("", "", nil, 11, false))).call(Gems::Request.parse("loner"))

    assert_equal [:compiles, "zr-crash"], [result.tier, result.kind]
  end

  def test_a_gem_that_fails_under_ruby_is_skipped
    result = trial(Runner.new(ruby: answer("", "probe.rb:2: uninitialized constant Foo (NameError)\n", 1))).call(Gems::Request.parse("loner"))

    assert_equal [:skipped, "ruby-error"], [result.tier, result.kind]
  end

  # Table, Triage, Top

  def test_the_table_keeps_one_sorted_row_for_each_gem
    path = File.join(@dir, "compat.tsv")
    table = Gems::Table.new(path)
    table.add(result("rack", :loads), commit: "abc", downloads: 10, date: "2026-09-29")
    table.add(result("abc", :fails, "build-error", "a\tb\nc"), commit: "abc", date: "2026-09-29")
    table.write
    again = Gems::Table.new(path)
    again.add(result("rack", :compiles, "output-diff"), commit: "def", date: "2026-09-30")
    again.write

    lines = File.read(path).lines(chomp: true)
    assert_equal Gems::Table::COLUMNS.join("\t"), lines.first
    assert_equal ["abc\t1.0\trubygems\tfails\tbuild-error\ta b c\tabc\t2026-09-29\t",
                  "rack\t1.0\trubygems\tcompiles\toutput-diff\t\tdef\t2026-09-30\t"], lines.drop(1)
  end

  def test_a_detail_with_quotes_is_quoted_as_a_tsv_reader_reads_it
    path = File.join(@dir, "compat.tsv")
    table = Gems::Table.new(path)
    table.add(result("erubi", :compiles, "output-diff", 'stdout line 2: ruby " ", zr "Escape"'), commit: "c", date: "2026-09-29")
    table.write

    assert_includes File.read(path), %("stdout line 2: ruby "" "", zr ""Escape""")
    assert_equal 'stdout line 2: ruby " ", zr "Escape"', Gems::Table.new(path)["erubi"].detail
  end

  def test_a_long_detail_is_cut
    assert_equal 200, Gems::Table.clean("x" * 500).size
  end

  def test_a_detail_names_no_path_of_this_machine
    detail = "ruby: #{Zr::Dev.path("tmp/gems/a.rb")}:5: error, and #{Dir.home}/.gem/b.rb:1"

    assert_equal "ruby: tmp/gems/a.rb:5: error, and ~/.gem/b.rb:1", Gems::Table.clean(detail)
  end

  def test_a_sweep_writes_each_row_and_line_as_its_gem_ends
    tables = %w[sweep.tsv compat.tsv].map { |name| Gems::Table.new(File.join(@dir, name)) }
    lines = []
    seen = []
    answers = { "rack" => result("rack", :loads), "cexty" => result("cexty", :refused, "cext:cexty") }
    sweep = Zr::Dev::Commands::Gems::Sweep.new("gems sweep")
    sweep.define_singleton_method(:downloads) { { "rack" => 7 } }
    sweep.define_singleton_method(:trial) { ->(request) { answers.fetch(request.name) } }
    say = lambda do |line|
      lines << line
      seen << tables.map { |table| Gems::Table.new(table.path).map(&:gem) }
    end

    results = sweep.sweep(%w[rack cexty].map { Gems::Request.parse(_1) }, tables, StringIO.new, say)

    assert_equal %w[rack cexty], results.map(&:name)
    assert_equal [[%w[rack], %w[rack]], [%w[cexty rack], %w[cexty rack]]], seen, "each line comes after its rows are on disk"
    assert_equal "7", Gems::Table.new(tables.first.path)["rack"].downloads
    assert_match %r{\A\[1/2\] loads +rack 1\.0 \(\d+s; 0m in all\)\z}, lines.first
    assert_match %r{\A\[2/2\] refused +cexty 1\.0  cext:cexty }, lines.last
  end

  def test_a_sweeps_top_ranks_are_a_count_or_a_range_from_one
    ranks = Zr::Dev::Commands::Gems::Sweep.method(:ranks)
    top = (1..30).map { "gem#{_1}" }

    assert_equal %w[gem1 gem2 gem3], top[ranks.call("3")]
    assert_equal %w[gem11 gem12], top[ranks.call("11..12")]
    assert_equal %w[gem29 gem30], top[ranks.call("29..40")], "a range past the list ends with it"
    assert_equal %w[gem7], top[ranks.call("7..7")]
    assert_equal [nil] * 4, %w[0 5..4 0..3 x].map { ranks.call(_1) }
  end

  def test_triage_ranks_the_causes_by_gems_then_downloads
    table = Gems::Table.new(File.join(@dir, "none.tsv"))
    table.add(result("a", :refused, "cext:a"), commit: "c", downloads: 5)
    table.add(result("b", :fails, "build-error"), commit: "c", downloads: 100)
    table.add(result("c", :fails, "build-error"), commit: "c", downloads: 1)
    table.add(result("d", :refused, "cext:d"), commit: "c", downloads: 50)
    table.add(result("e", :loads), commit: "c", downloads: 1000)
    groups = Gems::Triage.new(table).groups

    assert_equal [["build-error", 2], ["cext:d", 1], ["cext:a", 1]], groups.map { |g| [g.kind, g.rows.size] }
    assert_equal %w[b c], groups.first.gems
    assert_equal %w[cext:d cext:a], Gems::Triage.new(table).groups("cext").map(&:kind)
  end

  def test_the_top_list_reads_what_it_writes
    path = File.join(@dir, "top.tsv")
    Gems::Top.write({ "rake" => 10, "rack" => 5 }, path)

    assert_equal({ "rake" => 10, "rack" => 5 }, Gems::Top.read(path))
  end

  # Gen::GemCompat

  def test_the_compat_page_counts_each_tier_and_lists_the_causes
    require_relative "../../tool/gen"
    require_relative "../../tool/gen/gem_compat"
    io = StringIO.new

    stub_method(Gems::Table, :compat, File.join(FIXTURES, "compat.tsv")) do
      Zr::Dev::Commands::Gen::GemCompat.new("gen gem-compat").write(io)
    end

    assert_includes io.string, "from log/gems/compat.tsv"
    assert_includes io.string, "The results come from"
    { "loads" => 2, "compiles" => 1, "builds" => 1, "fails" => 1, "refused" => 2, "skipped" => 1, "all" => 8 }.each do |tier, count|
      assert_includes io.string, "| #{tier} | #{count} |\n"
    end
    assert_match(/^\| `cext:nokogiri` \| 2 \| zeta, eta \|$/, io.string)
  end

  # The table is not committed, so a checkout without one keeps the page.
  def test_the_compat_page_stops_without_a_table
    require_relative "../../tool/gen"
    require_relative "../../tool/gen/gem_compat"

    _, err = capture_io do
      stub_method(Gems::Table, :compat, File.join(@dir, "compat.tsv")) do
        assert_raises(SystemExit) { Zr::Dev::Commands::Gen::GemCompat.new("gen gem-compat").write(StringIO.new) }
      end
    end

    assert_includes err, "run `zr-dev gems sweep --save`"
  end

  private

  def resolver = Gems::Resolver.new(store: Gems::FetchedGems.new(@dir), corpus: CORPUS, offline: true, remote: nil)

  # A C scan that keeps its scans in the test's directory.
  def c_scan = Gems::CScan.new(dir: File.join(@dir, "capi"))

  def trial(runner)
    Gems::Trial.new(resolver: resolver, runner: runner, overrides: OVERRIDES, logs: File.join(@dir, "logs"), c_scan: c_scan,
                    work: File.join(@dir, "work"), reference: Reference)
  end

  # The reference ruby, with no environment of its own.
  module Reference
    def self.env = {}
  end

  # A gem `name` at `version` below the test's directory, with a gemspec
  # that lists `deps` (`{ name => requirement }`) and an empty lib/.
  def gem_dir(rel, version, deps = {})
    dir = File.join(@dir, rel)
    name = File.basename(rel)
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |s|
        s.name = #{name.dump}
        s.version = #{version.dump}
        s.summary = "a fixture"
        s.authors = ["zr"]
        #{deps.map { |dep, requirement| "s.add_dependency #{dep.dump}, #{requirement.dump}" }.join("\n  ")}
      end
    RUBY
    dir
  end

  # An unpacked json at `version`, with its C extension.
  def json_at(version)
    dir = File.join(@dir, "json-#{version}")
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "lib/json.rb"), "")
    File.write(File.join(dir, ".zr-corpus-version"), version)
    File.write(File.join(dir, ".zr-corpus-spec"), '{"extensions":["ext/json/extconf.rb"],"require_paths":["lib"]}')
    dir
  end

  def answer(stdout, stderr = "", status = 0) = Zr::Diff::Answer.new(stdout, stderr, status, nil, false)

  def result(name, tier, kind = nil, detail = nil)
    Gems::Result.new(name: name, version: "1.0", source: "rubygems", tier: tier, kind: kind, detail: detail, log: nil)
  end

  # Answers for each step of a trial: `build`, `ruby` and `zr` (the
  # binary). By default each one succeeds, and ruby and zr agree.
  class Runner
    attr_reader :steps, :argvs, :homes

    def initialize(**answers)
      same = Zr::Diff::Answer.new("Only Module\n  \n", "", 0, nil, false)
      @answers = { build: Zr::Diff::Answer.new("", "", 0, nil, false), ruby: same, zr: same }.merge(answers)
      @steps = []
      @argvs = []
      @homes = []
    end

    # For ruby, what its GEM_PATH holds: each specification, and where
    # each gem's link leads.
    def run(argv, env: {}, **)
      step = if argv.include?("build") then :build
             elsif argv.first.start_with?("./") then :zr
             else :ruby
             end
      @steps << step
      if step == :ruby
        home = env.fetch("GEM_PATH", "").split(File::PATH_SEPARATOR).last.to_s
        @homes << Dir.glob("#{home}/specifications/*.gemspec").map { |spec| File.basename(spec) }.sort +
                  Dir.glob("#{home}/gems/*").map { |link| File.readlink(link) }.sort
      end
      @argvs << argv
      [@answers.fetch(step), nil]
    end
  end

  # A .gem file of `name` at `version` with `files`, built in the test's
  # directory.
  def package(name, version, files)
    dir = File.join(@dir, "build-#{name}-#{version}")
    files.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), text)
    end
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.summary = "a fixture"
      s.authors = ["zr"]
      s.files = files.keys
    end
    Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) { Dir.chdir(dir) { File.join(dir, Gem::Package.build(spec)) } }
  end
end
