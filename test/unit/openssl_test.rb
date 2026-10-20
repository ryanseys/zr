# frozen_string_literal: true
# zr-test: runtime
# zr-test: on macho

require "test_helper"
require_relative "../support/harness/requirements"

# `require "openssl"` opens the host's libssl 3 when the program runs.
# When the library is not there, it raises LoadError with a message that
# gives each path it tried. A program that rescues the error continues.
# ruby links its OpenSSL in, so no corpus recording can contain this
# output. This test checks it.
class OpenSSLTest < Minitest::Test
  PROGRAM = <<~RUBY
    begin
      require "openssl"
      puts OpenSSL::Digest.hexdigest("SHA256", "zr")
    rescue LoadError => e
      puts "LoadError: \#{e.message}"
    end
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  def test_a_missing_library_raises_load_error_at_require
    ran = run_program("OPENSSL_DIR" => "/nonexistent")
    assert_equal "LoadError: OpenSSL 3 was not found; set OPENSSL_DIR to its prefix. " \
                 "Looked for: /nonexistent/lib/libssl.3.dylib (no such file)\n", ran
  end

  def test_digest_uses_host_library_when_present
    skip "libssl 3 is not installed" unless Zr::Harness::Requirements.macos_libssl?

    assert_equal "#{`printf zr | shasum -a 256`.split.first}\n", run_program({})
  end

  private

  # Runs the program with `zr run` and returns its stdout. The program is
  # at a fixed path, so the run cache keeps its binary for every worker
  # and every later run; each test built it again with `zr build`, 18 s.
  def run_program(env)
    answer = Checks.run([RbConfig.ruby, "--disable-gems", File.join(ROOT, "exe/zr"), "run", program], env: env)
    assert_nil Checks.killed(answer), "the program was killed"
    answer.stdout
  end

  def program
    path = File.join(ROOT, "tmp", "test-openssl", "require_openssl.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, PROGRAM) unless File.exist?(path) && File.read(path) == PROGRAM
    path
  end
end
