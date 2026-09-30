# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/gems"

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

  # Corpus

  def test_the_corpus_reads_the_markers_and_the_gemspec
    tiny = CORPUS.find("tiny")

    assert_equal ["tiny", "1.0.0", "corpus", ["lib"], []], [tiny.name, tiny.version, tiny.source, tiny.require_paths, tiny.extensions]
    assert_equal [["helper", ">= 1.1"], ["json", ">= 2"]], tiny.dependencies
    assert_equal "1.2.0", CORPUS.find("helper").version
    assert_equal ["ext/cexty/extconf.rb"], CORPUS.find("cexty").extensions
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

  def test_the_resolver_goes_past_zrs_version_when_another_gem_needs_an_older_one
    corpus = gem_dir("corpus/minitest", "5.25.0")
    gem_dir("corpus/old", "1.0.0", "minitest" => "< 6")
    root = gem_dir("root", "1.0.0", "minitest" => ">= 0", "old" => ">= 1")
    resolver = Gems::Resolver.new(store: Gems::Store.new(@dir), corpus: Gems::Corpus.new(File.dirname(corpus)), offline: true, remote: nil)
    _, deps = resolver.resolve(Gems::Request.parse(root))

    assert_equal ["minitest 5.25.0", "old 1.0.0"], deps.map(&:to_s).sort
  end

  def test_the_sets_keep_each_platform_of_a_version
    specs = %w[arm64-darwin ruby].map do |platform|
      Gem::Specification.new do |s|
        s.name = "native"
        s.version = "1.0.0"
        s.platform = platform
      end
    end
    set = Class.new(Gem::Resolver::Set) { define_method(:find_all) { |_| specs } }.new
    request = Gem::Resolver::DependencyRequest.new(Gem::Dependency.new("native"), nil)

    assert_equal %w[arm64-darwin ruby], Gems::Resolver::Preferred.new([set, set]).find_all(request).map { |s| s.platform.to_s }
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

  # Store

  def test_the_store_unpacks_a_gem_and_reads_it_back
    store = Gems::Store.new(@dir)
    subject = store.unpack(package("packed", "0.4.0", "lib/packed.rb" => "module Packed; end\n"))

    assert_equal ["packed", "0.4.0", "rubygems", File.join(store.src, "packed-0.4.0")], [subject.name, subject.version, subject.source, subject.root]
    assert File.file?(File.join(subject.root, "lib/packed.rb"))
    assert_equal "packed", Gem::Specification.load(File.join(subject.root, "packed.gemspec")).name, "zr build --gem reads this gemspec"
    assert_equal [subject], store.versions("packed")
    assert_equal subject, store.find("packed", "0.4.0")
    assert_equal subject, store.unpack(package("packed", "0.4.0", "lib/packed.rb" => "module Packed; end\n"))
  end

  def test_offline_the_resolver_takes_the_newest_version_in_the_store
    store = Gems::Store.new(@dir)
    store.unpack(package("packed", "0.4.0", "lib/packed.rb" => ""))
    store.unpack(package("packed", "0.10.0", "lib/packed.rb" => ""))

    assert_equal "0.10.0", Gems::Resolver.new(store: store, offline: true, remote: nil).find(Gems::Request.parse("packed")).version
  end

  # Rules

  def test_a_gem_with_a_c_extension_is_refused
    failure = Gems::Rules.refusal([CORPUS.find("tiny"), CORPUS.find("cexty")])

    assert_equal ["cext:cexty", :refused], [failure.kind, failure.tier]
  end

  def test_a_port_outside_its_range_is_refused_and_inside_it_is_not
    json = CORPUS.find("json")

    assert_equal "port-range:json", Gems::Rules.refusal([json]).kind
    assert_nil Gems::Rules.refusal([json.with(version: Zr::Ports::ALL["json"].version)])
  end

  # Override

  def test_an_override_skips_a_gem_or_names_its_requires
    assert_equal "needs a running server", Gems::Override.for("skipped", dir: OVERRIDES).skip
    parts = Gems::Override.for("multi-part", dir: OVERRIDES)
    assert_equal [nil, ["multi/part"], false], [parts.skip, parts.requires, parts.smoke?]
    assert Gems::Override.for("tiny", dir: OVERRIDES).smoke?
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
    trial(runner).call(Gems::Request.parse(json_at(Zr::Ports::ALL["json"].version)))

    refute_includes runner.argvs[0], "--gem"
  end

  def test_ruby_finds_each_gem_on_its_gem_path_too
    runner = Runner.new
    trial(runner).call(Gems::Request.parse("tiny"))

    assert_equal ["helper-1.2.0.gemspec", "tiny-1.0.0.gemspec", CORPUS.find("helper").root, CORPUS.find("tiny").root], runner.homes.first
  end

  def test_a_smoke_program_that_gives_rubys_output_verifies_the_gem
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse("tiny"))

    assert_equal :verified, result.tier
    assert_equal %i[build ruby zr build ruby zr], runner.steps
    assert_includes runner.argvs.first, "helper=#{CORPUS.find("helper").root}", "each dependency is a --gem"
  end

  def test_a_trial_builds_with_the_zr_that_it_is_given
    runner = Runner.new
    Gems::Trial.new(resolver: resolver, runner: runner, overrides: OVERRIDES, logs: File.join(@dir, "logs"),
                    work: File.join(@dir, "work"), reference: Reference, zr: "/copy/exe/zr").call(Gems::Request.parse("helper"))

    assert_equal "/copy/exe/zr", runner.argvs.first[1]
  end

  def test_a_snapshot_is_a_directory_with_a_zr
    error = assert_raises(ArgumentError) { Gems::Snapshot.new(@dir) }
    assert_includes error.message, "no exe/zr"
    assert_equal File.join(Zr::Dev::ROOT, "exe/zr"), Gems::Snapshot.new(Zr::Dev::ROOT).zr
  end

  def test_an_override_skips_a_gem_before_it_is_found
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse("skipped"))

    assert_equal [:skipped, "skip", "needs a running server"], [result.tier, result.kind, result.detail]
    assert_empty runner.steps
  end

  def test_a_refused_gem_is_never_built
    runner = Runner.new
    result = trial(runner).call(Gems::Request.parse("cexty"))

    assert_equal [:refused, "cext:cexty"], [result.tier, result.kind]
    assert_empty runner.steps
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

  private

  def resolver = Gems::Resolver.new(store: Gems::Store.new(@dir), corpus: CORPUS, offline: true, remote: nil)

  def trial(runner)
    Gems::Trial.new(resolver: resolver, runner: runner, overrides: OVERRIDES, logs: File.join(@dir, "logs"),
                    work: File.join(@dir, "work"), reference: Reference)
  end

  # The reference ruby, without tmp/reference.
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
    File.write(File.join(dir, ".zeo-probe-version"), version)
    File.write(File.join(dir, ".zeo-probe-spec"), '{"extensions":["ext/json/extconf.rb"],"require_paths":["lib"]}')
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
