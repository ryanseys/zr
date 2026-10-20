# frozen_string_literal: true

require "test_helper"

# The gem that `gem build zr.gemspec` makes: every file that the `zr`
# command can load is in it, nothing in it names this machine, and it
# depends on no other gem.
class GemspecTest < Minitest::Test
  # The directories whose tracked files the command reads at run time.
  SHIPPED = %r{\A(exe|lib|licenses|vendor/(ruby|LICENSES|targets))/}

  def spec = (@@spec ||= Dir.chdir(ROOT) { Gem::Specification.load("zr.gemspec") })

  def tracked = (@@tracked ||= IO.popen(%w[git ls-files -z], chdir: ROOT, &:read).split("\0"))

  def test_the_gem_has_every_file_that_the_command_reads
    missing = tracked.grep(SHIPPED) - spec.files
    assert_empty missing
    assert_includes spec.files, "exe/zr"
    assert_includes spec.executables, "zr"
  end

  # A platform gem (ZR_GEM_PLATFORM) carries its host's runtime, unpacked
  # under data/runtime (Prebuilt.bundled); without its runtime, the
  # gemspec refuses. The `ruby` gem carries none.
  def test_a_platform_gem_carries_the_runtime_that_it_names
    dir = "data/runtime/zr-test-#{Process.pid}"
    FileUtils.mkdir_p(File.join(ROOT, dir, "store/meta/ab"))
    File.write(File.join(ROOT, dir, "manifest.json"), "{}")
    File.write(File.join(ROOT, dir, "store/meta/ab/x.json"), "{}")
    platform = fresh_spec("ZR_GEM_PLATFORM" => "arm64-darwin", "ZR_GEM_RUNTIME" => dir)

    assert_equal "arm64-darwin", platform.platform.to_s
    assert_equal ["#{dir}/manifest.json", "#{dir}/store/meta/ab/x.json"], platform.files.grep(%r{\Adata/})
    assert_equal Gem::Platform::RUBY, spec.platform.to_s
    assert_empty spec.files.grep(%r{\Adata/})
    assert_raises(RuntimeError) { fresh_spec("ZR_GEM_PLATFORM" => "arm64-darwin", "ZR_GEM_RUNTIME" => "data/runtime/none") }
  ensure
    FileUtils.rm_rf(File.join(ROOT, dir))
  end

  # The gemspec read again under `env`: Gem::Specification.load keeps
  # the first spec of a path.
  def fresh_spec(env)
    path = File.join(ROOT, "zr.gemspec")
    with_env(env) { Dir.chdir(ROOT) { eval(File.read(path), TOPLEVEL_BINDING, path) } }
  end

  # A `require_relative` in lib/ or exe/zr that leaves the gem's files
  # would work in a checkout and fail in an install.
  def test_each_require_relative_stays_in_the_gem
    files = spec.files.to_h { |file| [file, true] }
    outside = spec.files.grep(%r{\A(exe/zr|lib/.*\.rb)\z}).flat_map do |file|
      File.read(File.join(ROOT, file)).scan(/^\s*require_relative\s+["']([^"'#]+)["']/).flatten.filter_map do |rel|
        target = File.expand_path(rel, File.dirname(File.join(ROOT, file))).delete_prefix("#{ROOT}/")
        target += ".rb" unless target.end_with?(".rb")
        "#{file}: #{rel}" unless files[target] || !tracked.include?(target)
      end
    end
    assert_empty outside
  end

  # The checkout's path or the home directory in a shipped file would be
  # a path of the machine that built the gem. Only a whole path counts: a
  # checkout at /zr is not named by `lib/zr/`.
  def test_no_file_names_this_machine
    here = Regexp.union([ROOT, Dir.home].map { |path| %r{(?<![\w./-])#{Regexp.escape(path)}/}n })
    named = spec.files.select { |file| File.binread(File.join(ROOT, file)).match?(here) }
    assert_empty named
  end

  def test_the_gem_depends_on_no_other_gem
    assert_empty spec.runtime_dependencies
    assert_equal [Gem::Requirement.new(">= #{Zr::RUBY_MINIMUM}")], [spec.required_ruby_version]
  end

  def test_the_links_name_this_version
    %w[documentation_uri changelog_uri].each do |key|
      assert_includes spec.metadata.fetch(key), "/v#{Zr::VERSION}/", key
    end
  end
end
