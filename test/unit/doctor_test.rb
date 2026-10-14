# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../lib/zr/doctor"

# `zr doctor` checks what zr needs on this host (lib/zr/doctor.rb), and
# `zr version`, `zr cache` and `zr run --emit wasm` tell the user where
# they stand.
class DoctorTest < Minitest::Test
  EXE = File.join(ROOT, "exe/zr")

  # A ruby older than any that zr runs on, and one of the series after
  # the pinned ruby's.
  def too_old = "#{Zr::RUBY_MINIMUM.to_i - 1}.4.7"
  def next_series = "#{Zr::RUBY.to_i}.#{Zr::RUBY.split(".")[1].to_i + 1}.0"

  def test_an_older_ruby_fails
    check = Zr::Doctor.ruby(too_old)

    assert_equal :fail, check.status
    assert_equal "#{too_old}; zr needs ruby #{Zr::RUBY_MINIMUM} or later. See #{Zr::DOCS_URL}/how-to/install.md", check.detail
  end

  def test_another_series_warns
    check = Zr::Doctor.ruby(next_series)

    assert_equal :warn, check.status
    assert_equal "#{next_series}; zr is tested with #{Zr::RUBY_PIN}", check.detail
  end

  def test_the_pinned_series_is_ok
    assert_equal :ok, Zr::Doctor.ruby(Zr::RUBY).status
    assert_equal :ok, Zr::Doctor.ruby("#{Zr::RUBY[/\A\d+\.\d+/]}.99").status
  end

  def test_a_host_that_cannot_run_its_binaries_warns
    check = Zr::Doctor.host("x86_64-linux")

    assert_equal :warn, check.status
    assert_includes check.detail, "--emit wasm"
  end

  def test_a_glibc_aarch64_host_runs_the_musl_target
    Checks.with_host("aarch64-linux-gnu") do
      check = Zr::Doctor.host
      assert_includes check.detail, "runs aarch64-linux-musl" if check.status == :ok
      assert_includes check.detail, "no cc to link a binary" if check.status == :warn
    end
  end

  def test_each_target_has_a_line_with_its_outputs_and_what_this_host_makes
    checks = Zr::Doctor.targets

    assert_equal Zr::Target.all.map(&:triple), checks.map { |c| c.detail.split.first }
    wasm = checks.find { |c| c.detail.start_with?("wasm32-wasi ") }
    assert_equal "target", wasm.name
    assert_equal :ok, wasm.status
    assert_equal "wasm32-wasi            wasm; this host: wasm", wasm.detail
  end

  def test_a_target_that_this_host_cannot_link_warns
    target = Zr::Target.fetch("aarch64-linux-musl")
    check = stub_method(Zr::Target, :tool?, false) { Zr::Doctor.targets([target]).first }

    assert_equal :warn, check.status
    assert_equal "aarch64-linux-musl     binary, obj; this host: obj", check.detail
  end

  def test_the_first_line_names_this_zr
    assert_equal "#{Zr::VERSION}  #{Zr::Paths::ROOT}", Zr::Doctor.zr.detail
  end

  def test_no_wasmtime_warns
    check = Zr::Doctor.wasmtime(nil)
    assert_equal :warn, check.status
    assert_includes check.detail, "https://wasmtime.dev"
  end

  def test_a_failed_check_makes_the_run_fail
    failing = Zr::Doctor::Check.new(:fail, "ruby", too_old)
    out = StringIO.new

    ran = stub_method(Zr::Doctor, :checks, [failing]) { Zr::Doctor.run(out) }

    refute ran
    assert_equal "fail  ruby               #{too_old}\n", out.string
  end

  def zr(*, env: {})
    # rubygems requires BUNDLER_SETUP at boot, so a bundle leaks through it too.
    unbundled = Zr::ChildRuby::UNBUNDLED
    Open3.capture3(unbundled.merge(env), RbConfig.ruby, EXE, *, chdir: ROOT)
  end

  def test_version_names_the_pinned_ruby
    out, _, status = zr("version")

    assert_predicate status, :success?
    assert_equal "zr #{Zr::VERSION} (for ruby #{Zr::RUBY_PIN})\n", out
  end

  def test_cache_prints_its_path
    Dir.mktmpdir("zr-cache-") do |dir|
      out, _, status = zr("cache", env: { "ZR_CACHE" => dir })

      assert_predicate status, :success?
      assert_equal "#{dir}\n", out
    end
  end

  def test_cache_clean_days_keeps_the_entries_used_in_those_days
    Dir.mktmpdir("zr-cache-") do |dir|
      old, young = %w[aa bb].map do |key|
        File.join(dir, "store", "parse", key, key * 32).tap do |path|
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "x")
        end
      end
      File.utime(Time.now - (3 * 86_400), Time.now - (3 * 86_400), old)

      out, _, status = zr("cache", "clean", "--days", "1", env: { "ZR_CACHE" => dir })

      assert_predicate status, :success?
      assert_match(/\Adeleted 1 file\(s\)/, out)
      refute_path_exists old
      assert_path_exists young
    end
  end

  def test_cache_clean_days_needs_a_number
    _, err, status = zr("cache", "clean", "--days", "soon")

    assert_equal 2, status.exitstatus
    assert_includes err, "--days needs a number of days, 0 or more"
  end

  def test_run_emit_wasm_without_wasmtime_stops_before_the_build
    Dir.mktmpdir("zr-no-wasmtime-") do |dir|
      program = File.join(dir, "app.rb")
      File.write(program, "p 1\n")

      _, err, status = zr("run", "--emit", "wasm", program, env: { "PATH" => dir })

      assert_equal 1, status.exitstatus
      assert_includes err, "needs wasmtime, and it is not on the PATH"
    end
  end

  # An installed gem as `Doctor.extensions` reads one.
  Spec = Data.define(:name, :gem_dir, :extension_dir, :extensions)

  DARWIN = Zr::Target::AARCH64_DARWIN.triple

  def test_c_extensions_are_for_aarch64_darwin_and_musl_only
    check = Zr::Doctor.extensions("x86_64-linux-gnu", [])

    assert_equal [:ok, "not on x86_64-linux-gnu; zr's ports stand in for them"], [check.status, check.detail]
    assert_match(/\A0 of 0 installed gems/, Zr::Doctor.extensions("aarch64-linux-musl", [], cc: "/usr/bin/cc", make: "/usr/bin/make").detail)
  end

  def test_c_extensions_without_cc_or_make_warn
    assert_match(/\Ano cc, which --native-ext needs/, Zr::Doctor.extensions(DARWIN, [], cc: nil).detail)
    check = Zr::Doctor.extensions(DARWIN, [], cc: "/usr/bin/cc", make: nil)

    assert_equal [:warn, "0 of 0 installed gems with one need nothing more of zr's C API; no make, which an extconf.rb with rules of its own needs"],
                 [check.status, check.detail]
  end

  # A gem whose bundle imports only what the C API has is ready; one that
  # imports a function it lacks, or that has no compiled extension, is not.
  def test_c_extensions_name_the_gems_that_the_c_api_covers
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    Dir.mktmpdir do |dir|
      specs = { "ready" => "rb_intern", "lacking" => "rb_not_a_function" }.map do |name, import|
        built = File.join(dir, name, "built")
        FileUtils.mkdir_p(built)
        c = File.join(dir, "#{name}.c")
        File.write(c, "unsigned long #{import}(const char *);\nunsigned long Init_#{name}(void) { return #{import}(\"x\"); }\n")
        system("cc", "-bundle", "-undefined", "dynamic_lookup", c, "-o", File.join(built, "#{name}.bundle"), exception: true)
        Spec.new(name, File.join(dir, name), built, ["ext/#{name}/extconf.rb"])
      end
      unbuilt = Spec.new("unbuilt", File.join(dir, "unbuilt"), File.join(dir, "none"), ["ext/unbuilt/extconf.rb"])
      ruby_only = Spec.new("plain", File.join(dir, "plain"), File.join(dir, "none"), [])

      check = Zr::Doctor.extensions(DARWIN, [*specs, unbuilt, ruby_only], cc: "/usr/bin/cc", make: "/usr/bin/make")

      assert_equal [:ok, "1 of 3 installed gems with one need nothing more of zr's C API: ready"], [check.status, check.detail]
    end
  end
end
