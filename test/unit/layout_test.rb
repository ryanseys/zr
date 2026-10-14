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
  # version itself.
  def test_ci_names_no_ruby_version
    ci = Dir[File.join(ROOT, ".github/**/*.yml")].sum("") { |path| File.read(path) }

    assert_equal [".ruby-version"], ci.scan(/ruby-version: (\S+)/).flatten.uniq, "the ruby setup-ruby installs"
    assert_empty ci.scan(/\bruby:\d/), "the container's ruby"
    assert_empty ci.scan(%r{ruby/ruby/\h{40}}), "the CRuby revision CI reads"
    assert_empty ci.scan(/--branch v\d/), "the prism tag CI reads"
  end

  # Each workflow that installs wasmtime pins the version that the tests
  # are run with.
  def test_ci_installs_the_wasmtime_of_the_harness
    require_relative "../support/harness/wasmtime"
    Dir[File.join(ROOT, ".github/workflows/*.yml")].each do |path|
      yml = File.read(path)
      next unless yml.include?("wasmtime/setup@")

      assert_equal [Zr::Harness::Wasmtime::VERSION], yml.scan(/^\s*WASMTIME_VERSION: (\S+)$/).flatten, path.delete_prefix("#{ROOT}/")
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

  # The release waits for each CI job by its name (ci_passed.rb), so each
  # name is one job's, with each matrix value put in.
  def test_each_ci_job_has_its_own_name
    require "yaml"
    load File.join(ROOT, ".github/scripts/ci_passed.rb")
    names = CIJobs.required

    assert_equal names.uniq, names
    assert_empty names.grep(/\$\{\{/)
    assert_includes names, "stock ruby, user cache (Linux)"
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
