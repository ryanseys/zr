# frozen_string_literal: true

require "test_helper"
require "zr/gem_set"
require "zr/hir"
require "zr/stdlib"

# The gems that a build reads before zr's standard library
# (lib/zr/gem_set.rb): `--gem` flags, then a Gemfile.lock under
# `BUNDLE_GEMFILE`. The gems here are directories with a gemspec, so no
# test reads the network or the host's installed gems.
class GemSetTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("zr-gem-set-")
    @env = { "ZR_CACHE" => File.join(@dir, "cache") }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A gem at `<dir>/<name>` with a gemspec and one file.
  def gem_dir(name, version, extensions: [])
    dir = File.join(@dir, name)
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "#{name}.rb"), "module #{name.capitalize}; end\n")
    File.write(File.join(dir, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |s|
        s.name = #{name.inspect}
        s.version = #{version.inspect}
        s.summary = "test"
        s.authors = ["zr"]
        s.files = ["lib/#{name}.rb"]
        s.extensions = #{extensions.inspect}
      end
    RUBY
    dir
  end

  def resolve(flags, env = {})
    with_env(@env.merge(env)) { Zr::GemSet.resolve(flags, env: ENV) }
  end

  def with_env(env)
    was = env.to_h { |name, _| [name, ENV[name]] }
    env.each { |name, value| ENV[name] = value }
    Zr::Paths.instance_variable_set(:@cache, nil)
    Zr::Config.instance_variable_set(:@current, nil) if Zr::Config.instance_variable_defined?(:@current)
    yield
  ensure
    was.each { |name, value| ENV[name] = value }
    Zr::Paths.instance_variable_set(:@cache, nil)
    Zr::Config.instance_variable_set(:@current, nil) if Zr::Config.instance_variable_defined?(:@current)
  end

  def test_no_flags_and_no_gemfile_is_the_empty_set
    set = resolve([], "BUNDLE_GEMFILE" => nil)

    assert_same Zr::GemSet::EMPTY, set
    assert_equal [], set.roots
  end

  def test_a_path_flag_gives_the_gemspecs_version_and_lib
    dir = gem_dir("rainbow", "3.1.1")

    gem = resolve([["rainbow", dir]], "BUNDLE_GEMFILE" => nil).gems.first

    assert_equal ["rainbow", "3.1.1", [File.join(dir, "lib")], nil], [gem.name, gem.version, gem.roots, gem.refusal]
  end

  def test_a_path_flag_to_a_directory_of_ruby_files_uses_it_as_a_root
    dir = File.join(@dir, "src")
    FileUtils.mkdir_p(dir)

    gem = resolve([["tool", dir]], "BUNDLE_GEMFILE" => nil).gems.first

    assert_equal [[dir], nil], [gem.roots, gem.version]
  end

  def test_a_missing_directory_is_unresolved
    error = assert_raises(Zr::GemSet::Unresolved) { resolve([["nope", File.join(@dir, "nope")]], "BUNDLE_GEMFILE" => nil) }

    assert_includes error.message, "no such directory"
  end

  def test_a_version_that_is_not_installed_names_the_install_command
    error = assert_raises(Zr::GemSet::Unresolved) { resolve([["csv", "99.0.0"]], "BUNDLE_GEMFILE" => nil) }

    assert_equal "--gem csv=99.0.0: csv 99.0.0 is not installed. Run 'gem install csv -v 99.0.0'", error.message
  end

  def test_a_gem_with_a_c_extension_is_refused_by_name
    dir = gem_dir("native", "1.0.0", extensions: ["ext/native/extconf.rb"])

    set = resolve([["native", dir]], "BUNDLE_GEMFILE" => nil)

    assert_match(/\Anative 1\.0\.0 \(--gem native=.+\) has a C extension, and zr has no port of it/, set.refusal(File.join(dir, "lib/native.rb")))
    assert_nil set.refusal(File.join(@dir, "other/lib/native.rb"))
  end

  def test_a_port_outside_its_compat_range_is_refused_and_inside_is_used
    old = gem_dir("json", "2.18.0", extensions: ["ext/json/extconf.rb"])

    refusal = resolve([["json", old]], "BUNDLE_GEMFILE" => nil).gems.first.refusal

    assert_includes refusal, "zr implements the C part of json #{Zr::Ports::ALL.fetch("json").compat} only"
  end

  def test_a_port_inside_its_compat_range_uses_zrs_c
    now = gem_dir("json", Zr::Ports::ALL.fetch("json").version, extensions: ["ext/json/extconf.rb"])

    assert_nil resolve([["json", now]], "BUNDLE_GEMFILE" => nil).gems.first.refusal
  end

  # An app whose Gemfile.lock names two path gems, as bundler writes it.
  # No test runs bundler to write it: zr's own bundler reads it.
  def app_with_lock
    app = File.join(@dir, "app")
    FileUtils.mkdir_p(app)
    gems = { "rainbow" => gem_dir("rainbow", "3.1.1"), "other" => gem_dir("other", "0.1.0") }
    File.write(File.join(app, "Gemfile"), gems.map { |name, dir| "gem #{name.inspect}, path: #{dir.inspect}\n" }.join)
    paths = gems.map do |name, dir|
      version = name == "rainbow" ? "3.1.1" : "0.1.0"
      "PATH\n  remote: #{dir}\n  specs:\n    #{name} (#{version})\n\n"
    end
    File.write(File.join(app, "Gemfile.lock"), <<~LOCK)
      #{paths.join.chomp}
      PLATFORMS
        ruby

      DEPENDENCIES
        other!
        rainbow!

      BUNDLED WITH
        #{Zr::Stdlib::DEFAULT.fetch("bundler")}
    LOCK
    File.join(app, "Gemfile")
  end

  def test_a_lock_applies_with_gemfile_and_a_flag_wins
    gemfile = app_with_lock
    flagged = File.join(@dir, "flagged")
    FileUtils.mkdir_p(flagged)

    set = with_env(@env.merge("BUNDLE_GEMFILE" => nil)) { Zr::GemSet.resolve([["rainbow", flagged]], gemfile: gemfile) }

    assert_equal [%w[rainbow --gem], %w[other Gemfile.lock]], set.gems.map { |gem| [gem.name, gem.source[/\A\S+/]] }
    assert_equal [flagged, File.join(@dir, "other/lib")], set.roots
  end

  def test_bundle_gemfile_names_the_lock_too
    gemfile = app_with_lock

    set = resolve([], "BUNDLE_GEMFILE" => gemfile)

    assert_equal %w[other rainbow], set.gems.map(&:name).sort
  end

  def test_zrs_own_development_gemfile_never_applies
    assert_same Zr::GemSet::EMPTY, resolve([], "BUNDLE_GEMFILE" => Zr::GemSet::OWN)
  end

  def test_a_gem_missing_from_the_host_names_the_fix
    gemfile = app_with_lock
    FileUtils.rm_rf(File.join(@dir, "other"))

    error = assert_raises(Zr::GemSet::Unresolved) { resolve([], "BUNDLE_GEMFILE" => gemfile) }

    assert_match(/other/, error.message)
  end

  def test_a_second_resolve_reads_the_cache
    dir = gem_dir("rainbow", "3.1.1")
    first = resolve([["rainbow", dir]], "BUNDLE_GEMFILE" => nil)

    kept = Dir[File.join(@dir, "cache/gems/*.set")]
    second = resolve([["rainbow", dir]], "BUNDLE_GEMFILE" => nil)

    assert_equal 1, kept.size
    assert_equal first.digest, second.digest
  end

  def test_a_removed_root_resolves_again
    dir = gem_dir("rainbow", "3.1.1")
    resolve([["rainbow", dir]], "BUNDLE_GEMFILE" => nil)
    kept = Dir[File.join(@dir, "cache/gems/*.set")].first

    FileUtils.rm_rf(File.join(dir, "lib"))

    assert_nil Zr::GemSet.kept(kept)
  end

  def set(*gems) = Zr::GemSet.new(gems.map { |fields| Zr::GemSet::Entry.new(refusal: nil, source: "--gem", **fields) })

  # A default gem has no root: its files are ruby's own library.
  def test_a_default_gem_is_refused_by_its_features
    json = set(name: "json", version: "2.18.0", roots: [], refusal: "json: no")
    io = set(name: "io-console", version: "0.1.0", roots: [], refusal: "io-console: no")

    assert_equal ["json: no", "json: no", nil], %w[json json/ext.rb jsonx].map { |feature| json.refusal(nil, feature) }
    assert_equal "io-console: no", io.refusal(nil, "io/console")
  end

  def test_a_gems_file_comes_before_zrs_standard_library
    lib = File.join(gem_dir("csv", "9.0.0"), "lib")
    main = File.join(@dir, "main.rb")

    hir = Zr::Hir.build(%(require "csv"\n), main, gem_set: set(name: "csv", version: "9.0.0", roots: [lib]))

    assert_equal [File.join(lib, "csv.rb")], hir.units.map(&:file)
  end

  def test_a_require_of_a_refused_gem_stops_the_build_at_its_line
    lib = File.join(gem_dir("native", "1.0.0"), "lib")
    main = File.join(@dir, "main.rb")
    gems = set(name: "native", version: "1.0.0", roots: [lib], refusal: "native 1.0.0 has a C extension")

    error = assert_raises(Zr::Refused) { Zr::Hir.build(%(x = 1\nrequire "native"\n), main, gem_set: gems) }

    assert_equal %(#{main}:2: require of "native": native 1.0.0 has a C extension), error.message
  end
end
