# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# Steep checks the kernel of each target at the strict level, with
# sig/zr/kern.rbs: the portable files with an OS layer and an
# architecture layer. Each target's kernel is a Steep project of its
# own, because Steep takes a file in one target only, and the targets
# share the portable files.
class KernelSteepTest < Minitest::Test
  LAYERS = { "darwin" => "aarch64", "linux" => "aarch64", "wasi" => "wasm32" }.freeze

  LAYERS.each do |os, arch|
    define_method("test_steep_checks_the_kernel_on_#{os}") do
      out, status = steep(os, arch)
      files = Dir[File.join(ROOT, "lib/zr/runtime/kernel/{*.rb,os/#{os}/*.rb,arch/#{arch}/*.rb}")]

      assert_predicate status, :success?, out
      refute_match(/\bFATAL\b/, out, "a Steep worker stopped, and its file is not checked")
      # Steep prints a dot for each file that it checks, and one for
      # sig/zr/kern.rbs.
      assert_equal files.size + 1, out[/^# Type checking files:\s+(\.+)$/, 1].to_s.size, out
      assert_match(/No type error detected/, out)
    end
  end

  private

  # Runs `steep check` on the portable kernel and the layers of `os` and
  # `arch`. A Steepfile's paths are relative to its directory, so the
  # project is in tmp/ of the repository.
  def steep(os, arch)
    FileUtils.mkdir_p(File.join(ROOT, "tmp"))
    Dir.mktmpdir("kernel-steep-", File.join(ROOT, "tmp")) do |dir|
      up = Pathname(ROOT).relative_path_from(Pathname(dir))
      kernel = "#{up}/lib/zr/runtime/kernel"
      steepfile = File.join(dir, "Steepfile")
      File.write(steepfile, <<~RUBY)
        target :kernel do
          signature "#{up}/sig/zr/kern.rbs"
          check "#{kernel}/*.rb", "#{kernel}/os/#{os}", "#{kernel}/arch/#{arch}", inline: true
          configure_code_diagnostics(Steep::Diagnostic::Ruby.strict)
        end
      RUBY
      Open3.capture2e(File.join(ROOT, "bin/steep"), "check", "--no-daemon", "--steepfile=#{steepfile}", "-j", "2", chdir: ROOT)
    end
  end
end
