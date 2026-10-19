# frozen_string_literal: true

require "test_helper"
require "zr/gem_set"
require "zr/hir"
require "zr/library/stdlib"

# The gems that a build reads, as ruby finds them (lib/zr/gem_set.rb): a
# Gemfile.lock under `BUNDLE_GEMFILE`, else the gems installed on
# rubygems' path. The gems here are in a gem home of the test's own, which
# GEM_HOME and GEM_PATH name, so no test reads the network or the host's
# installed gems.
class GemSetTest < Minitest::Test
  def setup
    @dir = File.realpath(Dir.mktmpdir("zr-gem-set-"))
    @home = File.join(@dir, "home")
    FileUtils.mkdir_p([File.join(@home, "gems"), File.join(@home, "specifications")])
    @env = { "ZR_CACHE" => File.join(@dir, "cache"), "GEM_HOME" => @home, "GEM_PATH" => @home, "BUNDLE_GEMFILE" => nil }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A gem at `<dir>/<name>` with a gemspec and one file, for a Gemfile's
  # `path:`.
  def gem_dir(name, version, extensions: [])
    dir = File.join(@dir, name)
    FileUtils.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "lib", "#{name}.rb"), "module #{name.capitalize}; end\n")
    File.write(File.join(dir, "#{name}.gemspec"), spec(name, version, extensions: extensions).to_ruby)
    dir
  end

  # A gem that rubygems installed in the test's gem home, as `gem install`
  # lays it out: its files, and its specification beside them.
  def installed(name, version, extensions: [], require_paths: ["lib"])
    dir = File.join(@home, "gems", "#{name}-#{version}")
    lib = File.join(dir, require_paths.first)
    FileUtils.mkdir_p(lib)
    File.write(File.join(lib, "#{name}.rb"), "module #{name.capitalize}; end\n")
    made = spec(name, version, extensions: extensions)
    made.require_paths = require_paths
    File.write(File.join(@home, "specifications", "#{name}-#{version}.gemspec"), made.to_ruby)
    dir
  end

  def spec(name, version, extensions: [])
    Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.summary = "test"
      s.authors = ["zr"]
      s.files = ["lib/#{name}.rb"]
      s.extensions = extensions
    end
  end

  def resolve(env = {}, requests: {})
    with_env(@env.merge(env)) { Zr::GemSet.resolve(env: ENV, requests: requests) }
  end

  def test_an_empty_gem_path_gives_only_ruby_s_default_gems
    set = resolve

    assert_equal [], set.roots + set.installed_roots
  end

  # rubygems' specification gives the version and the require paths.
  def test_an_installed_gem_gives_its_specifications_version_and_require_paths
    dir = installed("rainbow", "3.1.1", require_paths: ["src"])

    gem = resolve.gems.find { |entry| entry.name == "rainbow" }

    assert_equal ["3.1.1", [File.join(dir, "src")], "installed", nil], [gem.version, gem.roots, gem.source, gem.refusal]
  end

  def test_the_newest_installed_version_wins_unless_the_program_asks_for_another
    installed("rainbow", "3.1.1")
    installed("rainbow", "2.0.0")

    assert_equal "3.1.1", resolve.gems.find { |gem| gem.name == "rainbow" }.version
    asked = resolve(requests: { "rainbow" => ["~> 2.0"] }).gems.find { |gem| gem.name == "rainbow" }
    assert_equal ["2.0.0", true], [asked.version, asked.requested]
  end

  def test_the_program_s_gem_calls_are_its_requests
    assert_equal({ "json" => ["2.19.1"], "rake" => [">= 1", "< 99"], "csv" => [] },
                 Zr::GemSet.requests(%(gem "json", "2.19.1"\n  gem("rake", ">= 1", "< 99")\ngem 'csv'\nx.gem "no"\n# gem "no"\n)))
  end

  # The resolver runs under the ruby that ZR_HOST_RUBY names.
  def test_the_resolver_runs_under_the_host_ruby
    installed("rainbow", "3.1.1")

    assert_equal "zr-no-such-ruby", with_env("ZR_HOST_RUBY" => "zr-no-such-ruby") { Zr::GemSet.ruby }
    gem = resolve({ "ZR_HOST_RUBY" => RbConfig.ruby }).gems.find { |entry| entry.name == "rainbow" }

    assert_equal "3.1.1", gem.version
  end

  def test_a_bundle_gemfile_that_does_not_exist_is_unresolved
    error = assert_raises(Zr::GemSet::Unresolved) { resolve({ "BUNDLE_GEMFILE" => File.join(@dir, "nope", "Gemfile") }) }

    assert_includes error.message, "does not exist"
  end

  def test_a_gem_with_a_c_extension_is_refused_by_name
    dir = installed("native", "1.0.0", extensions: ["ext/native/extconf.rb"])

    set = resolve

    assert_match(/\Anative 1\.0\.0 \(installed\) has a C extension, and zr has no port of it/, set.refusal(File.join(dir, "lib/native.rb")))
    assert_nil set.refusal(File.join(@dir, "other/lib/native.rb"))
    assert set.gems.find { |gem| gem.name == "native" }.native, "only its C part is refused"
  end

  # Ruby's default json is newer, so the program asks for the old one.
  def test_a_port_outside_its_compat_range_compiles_its_ruby_and_needs_its_own_c
    installed("json", "2.18.0", extensions: ["ext/json/extconf.rb"])

    gem = resolve(requests: { "json" => ["2.18.0"] }).gems.find { |entry| entry.name == "json" }

    assert_includes gem.refusal, "zr implements the C part of json #{Zr::Library::Ports::ALL.fetch("json").compat} only"
    assert_includes gem.refusal, "--native-ext json=2.18.0"
    assert gem.native, "only its C part is refused"
  end

  def test_a_port_inside_its_compat_range_uses_zrs_c
    version = Zr::Library::Ports::ALL.fetch("json").version
    installed("json", version, extensions: ["ext/json/extconf.rb"])

    assert_nil resolve(requests: { "json" => [version] }).gems.find { |gem| gem.name == "json" }.refusal
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
        #{Zr::Library::Stdlib::DEFAULT.fetch("bundler")}
    LOCK
    File.join(app, "Gemfile")
  end

  # A bundle's gems come before zr's standard library, as `bundle exec`
  # puts them on the load path.
  def test_bundle_gemfile_names_the_lock
    gemfile = app_with_lock

    set = resolve({ "BUNDLE_GEMFILE" => gemfile })

    assert_equal %w[other rainbow], set.gems.map(&:name).sort
    assert_equal %w[Gemfile.lock], set.gems.map(&:source).uniq
    assert_equal [File.join(@dir, "other/lib"), File.join(@dir, "rainbow/lib")], set.roots.sort
  end

  def test_zrs_own_development_gemfile_never_applies
    installed("rainbow", "3.1.1")

    assert_equal %w[installed], resolve({ "BUNDLE_GEMFILE" => Zr::GemSet::OWN }).gems.map(&:source).uniq
  end

  def test_a_gem_missing_from_the_host_names_the_fix
    gemfile = app_with_lock
    FileUtils.rm_rf(File.join(@dir, "other"))

    error = assert_raises(Zr::GemSet::Unresolved) { resolve({ "BUNDLE_GEMFILE" => gemfile }) }

    assert_match(/other/, error.message)
  end

  def test_a_second_resolve_reads_the_cache
    installed("rainbow", "3.1.1")
    first = resolve

    kept = Dir[File.join(@dir, "cache/store/gems/*/*.marshal")]
    second = resolve

    assert_equal 1, kept.size
    assert_equal first.digest, second.digest
  end

  # `gem install` writes a specification, which the key reads.
  def test_an_install_resolves_again
    resolve
    installed("rainbow", "3.1.1")
    # The directory's time can be the same within a second.
    File.utime(Time.now + 5, Time.now + 5, File.join(@home, "specifications"))

    assert_equal ["rainbow"], resolve.gems.map(&:name) & ["rainbow"]
  end

  def test_a_removed_root_resolves_again
    dir = installed("rainbow", "3.1.1")
    resolve
    kept = Marshal.load(File.binread(Dir[File.join(@dir, "cache/store/gems/*/*.marshal")].first))

    FileUtils.rm_rf(File.join(dir, "lib"))

    assert_nil Zr::GemSet.kept(kept)
  end

  def set(*gems) = Zr::GemSet.new(gems.map { |fields| Zr::GemSet::Entry.new(refusal: nil, source: "Gemfile.lock", **fields) })

  # A default gem has no root: its files are ruby's own library.
  def test_a_default_gem_is_refused_by_its_features
    json = set(name: "json", version: "2.18.0", roots: [], refusal: "json: no")
    io = set(name: "io-console", version: "0.1.0", roots: [], refusal: "io-console: no")

    assert_equal ["json: no", "json: no", nil], %w[json json/ext.rb jsonx].map { |feature| json.refusal(nil, feature) }
    assert_equal "io-console: no", io.refusal(nil, "io/console")
  end

  def test_a_bundled_gems_file_comes_before_zrs_standard_library
    lib = File.join(gem_dir("csv", "9.0.0"), "lib")
    main = File.join(@dir, "main.rb")

    hir = Zr::Hir.build(%(require "csv"\n), main, Zr::BuildOptions.new(gem_set: set(name: "csv", version: "9.0.0", roots: [lib])))

    # A require finds the file by the real path of its directory.
    assert_equal [File.join(File.realpath(lib), "csv.rb")], hir.units.map(&:file)
  end

  # ruby searches its load path first, and its installed gems after it,
  # but activates the newest version of a default gem and the version that
  # the program asks for (rubygems/core_ext/kernel_require.rb).
  def test_an_installed_gem_comes_after_zrs_standard_library_unless_newer_or_asked_for
    csv = Zr::Library::Stdlib::BUNDLED.fetch("csv")
    lib = File.join(@dir, "csv/lib")
    files = lambda do |version, requested|
      gems = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "csv", version: version, source: "installed", roots: [lib], refusal: nil,
                                                   requested: requested)])
      [gems.roots, gems.installed_roots]
    end

    assert_equal [[], [lib]], files.call(csv, false)
    assert_equal [[lib], []], files.call("99.0.0", false)
    assert_equal [[lib], []], files.call("0.0.1", true)
  end

  # A gem whose own C the build links (`--native-ext`) takes its Ruby
  # half from the same install as its C, even at zr's own version.
  def test_a_gem_that_native_ext_names_comes_before_zrs_standard_library
    csv = Zr::Library::Stdlib::BUNDLED.fetch("csv")
    dir = installed("csv", csv)

    set = Zr::Config.with(ZR_NATIVE_EXT: "csv=#{csv}") { resolve }

    assert_equal [[File.join(dir, "lib")], []], [set.roots, set.installed_roots]
  end

  # A gem whose C extension zr does not port compiles but for its C part:
  # a require of that part, which no root holds, raises LoadError if it
  # runs, and the build says so once.
  def test_a_gem_with_an_unported_c_extension_compiles_its_ruby_files
    lib = File.join(gem_dir("native", "1.0.0"), "lib")
    File.write(File.join(lib, "native.rb"), "begin\n  require \"native/native\"\nrescue LoadError\n  NATIVE = :fallback\nend\n")
    main = File.join(@dir, "main.rb")
    gems = set(name: "native", version: "1.0.0", roots: [lib], refusal: "native 1.0.0 (Gemfile.lock) has a C extension, and zr has no port of it",
               native: true)

    hir = nil
    _, err = capture_io { hir = Zr::Hir.build(%(require "native"\nrequire "native"\n), main, Zr::BuildOptions.new(gem_set: gems)) }

    assert_equal [File.join(File.realpath(lib), "native.rb")], hir.units.map(&:file)
    assert_equal 1, err.scan("native 1.0.0 (Gemfile.lock) has a C extension").size
    assert_includes err, "a require of its C part raises LoadError if it runs"
  end

  def test_a_require_of_a_refused_gem_stops_the_build_at_its_line
    lib = File.join(gem_dir("native", "1.0.0"), "lib")
    main = File.join(@dir, "main.rb")
    gems = set(name: "native", version: "1.0.0", roots: [lib], refusal: "native 1.0.0 has a C extension")

    error = assert_raises(Zr::Refused) { Zr::Hir.build(%(x = 1\nrequire "native"\n), main, Zr::BuildOptions.new(gem_set: gems)) }

    assert_equal %(#{main}:2: require of "native": native 1.0.0 has a C extension), error.message
  end
end
