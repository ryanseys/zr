# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/answer"

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
    skip "libssl 3 is not installed" unless Zr::Harness::Needs.met?("libssl", "macos")

    assert_equal "#{`printf zr | shasum -a 256`.split.first}\n", run_program({})
  end

  private

  # Runs the program and returns its stdout. The binary is built once per process.
  def run_program(env)
    answer = Checks.run([binary], env: env)
    assert_nil Checks.killed(answer), "the program was killed"
    answer.stdout
  end

  def binary
    self.class.instance_variable_get(:@binary) || self.class.instance_variable_set(:@binary, build)
  end

  def build
    dir = Dir.mktmpdir("zr-openssl-")
    Minitest.after_run { FileUtils.rm_rf(dir) }
    rb = File.join(dir, "require_openssl.rb")
    File.write(rb, PROGRAM)
    bin = File.join(dir, "require_openssl")
    out = IO.popen([RbConfig.ruby, "--disable-gems", File.join(ROOT, "exe/zr"), "build", rb, "-o", bin],
                   err: %i[child out], &:read)
    assert_predicate $?, :success?, "the build failed: #{out}"
    bin
  end
end
