# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/version"

# The layout rules of the repository. The tools live in tool/, and the
# Rakefile keeps only the standard entry points. The ruby version has one
# source, `.ruby-version`: `zr-dev gen ruby_version` records it
# (lib/zr/ruby_version.rb), and every other fact is derived from the record.
class LayoutTest < Minitest::Test
  # Enough for the standard tasks and their comments. A tool with its own
  # logic belongs in tool/.
  RAKEFILE_LINES = 100

  def read(rel) = File.read(File.join(ROOT, rel))

  def test_no_rakelib_directory
    refute_path_exists File.join(ROOT, "rakelib"), "a tool is a zr-dev command in tool/, not a rake task in rakelib/"
  end

  def test_the_rakefile_stays_short
    lines = read("Rakefile").lines.size

    assert_operator lines, :<=, RAKEFILE_LINES, "the Rakefile has #{lines} lines; move the logic to tool/"
  end

  def test_the_record_names_the_pinned_ruby
    assert_equal Zr::RUBY_PIN, read(".ruby-version").strip
  end

  # The constants that a program sees, and its library directories, come
  # from the record.
  def test_the_runtime_constants_agree_with_the_record
    require_relative "../../tool/lib/zr/dev"
    require_relative "../../tool/gen/ruby_version"
    gen = Zr::Dev::Commands::Gen::RubyVersion

    assert_equal gen.runtime_text(gen.recorded), read(gen::RUNTIME)
  end

  # The pinned ruby gives the record's values itself.
  def test_the_record_agrees_with_the_pinned_ruby
    skip "this is #{RUBY_DESCRIPTION}, not ruby #{Zr::RUBY_PIN}" unless Zr.pinned_ruby?

    assert_equal [RUBY_RELEASE_DATE, RUBY_COPYRIGHT], [Zr::RUBY_RELEASE_DATE, Zr::RUBY_COPYRIGHT]
    # Up to the +PRISM, which a JIT that the run turned on can follow.
    assert_equal RUBY_DESCRIPTION[/\A[^)]*\)/], Zr::RUBY_DESCRIPTION_HEAD[/\A[^)]*\)/]
    assert_equal [RbConfig::CONFIG["ruby_version"], RbConfig::CONFIG["RUBY_API_VERSION"]], [Zr::RUBY_LIB_VERSION, Zr::RUBY_API]
  end

  # CI reads the ruby from `.ruby-version` and the record, and names no
  # version itself. The setup action passes on the version that a job
  # gives it, `.ruby-version` when the job gives none.
  def test_ci_names_no_ruby_version
    ci = Dir[File.join(ROOT, ".github/**/*.yml")].sum("") { |path| File.read(path) }

    others = Zr::RUBY_TESTED - [Zr::RUBY.split(".").first(2).join(".")]
    assert_equal [".ruby-version", *others.map { %("#{_1}") }].sort, ci.scan(/ruby-version: (?!\$\{\{)(\S+)/).flatten.uniq.sort,
                 "the ruby setup-ruby installs: the pinned one, and the other tested series"
    assert_empty ci.scan(/\bruby:\d/), "the container's ruby"
    assert_empty ci.scan(%r{ruby/ruby/\h{40}}), "the CRuby revision CI reads"
    assert_empty ci.scan(/--branch v\d/), "the prism tag CI reads"
  end

  # Each workflow that installs wasmtime, itself or through the setup
  # action, pins the version that the tests are run with, and each setup
  # takes it.
  def test_ci_installs_the_wasmtime_of_the_harness
    require_relative "../support/harness/wasmtime"
    Dir[File.join(ROOT, ".github/workflows/*.yml")].each do |path|
      yml = File.read(path)
      next unless yml.include?("wasmtime/setup@") || yml.include?("./.github/actions/setup")

      assert_equal [Zr::Harness::Wasmtime::VERSION], yml.scan(/^\s*WASMTIME_VERSION: (\S+)$/).flatten, path.delete_prefix("#{ROOT}/")
    end
    Dir[File.join(ROOT, ".github/{workflows/*.yml,actions/*/action.yml}")].each do |path|
      yml = File.read(path)
      assert_equal yml.scan("wasmtime/setup@").size, yml.scan("version: ${{ env.WASMTIME_VERSION }}").size, "each setup in #{path} takes the version"
    end
  end

  # CI fetches CRuby and prism through .github/scripts/fetch_sources.rb,
  # which reads the record and the vendor lock, so no workflow names them.
  def test_ci_fetches_the_c_sources_through_one_script
    Dir[File.join(ROOT, ".github/**/*.yml")].each do |path|
      refute_match %r{github\.com/ruby/(ruby|prism)}, File.read(path), path.delete_prefix("#{ROOT}/")
    end
  end

  # ci-ok is the one check that branch protection requires, so it needs
  # every job but the prerelease, and RuboCop and Steep only report. The
  # prerelease does not wait for ci-ok: it takes each lane that passed,
  # and its own step stops it when a tier 1 lane did not
  # (docs/how-to/release.md).
  def test_ci_ok_needs_every_job_that_can_fail_the_run
    require "yaml"
    jobs = YAML.load_file(File.join(ROOT, ".github/workflows/ci.yml")).fetch("jobs")

    assert_equal (jobs.keys - %w[ci-ok release]).sort, jobs.fetch("ci-ok").fetch("needs").sort
    release = jobs.fetch("release")
    assert_equal %w[checks lane smoke units], release.fetch("needs").sort
    assert_includes release.fetch("if"), "!cancelled()"
    assert(release.fetch("steps").any? { |step| step["run"].to_s.include?("passed-$triple") })
    assert_equal "always()", jobs.fetch("ci-ok").fetch("if")
    reports = jobs.fetch("checks").fetch("steps").select { |step| step["run"].to_s.match?(/rubocop|steep/) }
    assert_equal 2, reports.size
    assert(reports.all? { |step| step["continue-on-error"] })
  end

  # The release takes the newest run of a commit whose release job
  # passed, whatever the run's own result: a pull request's run does not
  # count.
  def test_the_release_takes_a_run_of_main_that_passed
    require_relative "../../.github/scripts/ci_passed"
    runs = [{ "id" => 1, "event" => "pull_request", "conclusion" => "success", "created_at" => "5" },
            { "id" => 2, "event" => "workflow_dispatch", "conclusion" => "success", "created_at" => "1" },
            { "id" => 3, "event" => "schedule", "conclusion" => "failure", "created_at" => "4" },
            { "id" => 4, "event" => "push", "conclusion" => "success", "created_at" => "2" }]

    assert_equal [3, 4, 2], CIGate.candidates(runs).map { |run| run["id"] }
    assert_empty CIGate.candidates(runs.first(1))
    assert CIGate.ok?([{ "name" => CIGate::JOB, "conclusion" => "success" }, { "name" => "ci-ok", "conclusion" => "failure" }])
    refute CIGate.ok?([{ "name" => CIGate::JOB, "conclusion" => "failure" }, { "name" => "ci-ok", "conclusion" => "success" }])
  end

  # CI runs zr on each ruby series that zr is tested with (RUBY_TESTED):
  # the pinned one from .ruby-version, and each other one by its number.
  def test_ci_runs_each_tested_ruby
    ci = File.read(File.join(ROOT, ".github/workflows/ci.yml"))
    others = Zr::RUBY_TESTED - [Zr::RUBY.split(".").first(2).join(".")]

    others.each { |series| assert_includes ci, %(ruby-version: "#{series}"), series }
  end

  # RuboCop checks zr's own code for the oldest ruby that runs it.
  def test_rubocop_targets_the_oldest_ruby_that_runs_zr
    assert_equal Zr::RUBY_MINIMUM, read(".rubocop.yml")[/TargetRubyVersion: (\S+)/, 1]
  end

  def test_the_tools_doc_names_every_command
    require_relative "../../tool/commands"
    doc = read("docs/reference/tools.md")

    Zr::Dev::COMMANDS.each_key { |word| assert_includes doc, "zr-dev #{word}", "docs/reference/tools.md" }
  end
end
