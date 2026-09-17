# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/case"

# `require "openssl"` opens the host's libssl 3 when the program runs.
# Where the library is absent it raises LoadError naming each place it
# looked, and a program that rescues it goes on. ruby links its OpenSSL
# in, so no corpus recording can hold this answer; the check holds it.
class OpenSSLTest < Minitest::Test
  PROGRAM = <<~RUBY
    begin
      require "openssl"
      puts OpenSSL::Digest.hexdigest("SHA256", "ze0")
    rescue LoadError => e
      puts "LoadError: \#{e.message}"
    end
  RUBY

  def setup
    skip "needs an aarch64-apple-darwin host" unless Ze0::Target::AARCH64_DARWIN.native?
  end

  def test_a_missing_library_raises_load_error_at_require
    ran = run_program("OPENSSL_DIR" => "/nonexistent")
    assert_equal "LoadError: OpenSSL 3 was not found; set OPENSSL_DIR to its prefix. " \
                 "Looked for: /nonexistent/lib/libssl.3.dylib (no such file)\n", ran
  end

  def test_the_host_library_answers_when_present
    skip "libssl 3 is not installed" unless Ze0::Harness::Needs.met?("libssl", "macos")

    assert_equal "#{`printf ze0 | shasum -a 256`.split.first}\n", run_program({})
  end

  private

  # The program's stdout, built once per process.
  def run_program(env)
    out, why = Checks.bounded(env, [binary], err: File::NULL)
    assert_nil why, "the program passed #{why}"
    out
  end

  def binary
    self.class.instance_variable_get(:@binary) || self.class.instance_variable_set(:@binary, build)
  end

  def build
    dir = Dir.mktmpdir("ze0-openssl-")
    Minitest.after_run { FileUtils.rm_rf(dir) }
    rb = File.join(dir, "require_openssl.rb")
    File.write(rb, PROGRAM)
    bin = File.join(dir, "require_openssl")
    out = IO.popen([RbConfig.ruby, "--disable-gems", File.join(ROOT, "bin/ze0"), "zr", "build", rb, "-o", bin],
                   err: %i[child out], &:read)
    assert $?.success?, "the build failed: #{out}"
    bin
  end
end
