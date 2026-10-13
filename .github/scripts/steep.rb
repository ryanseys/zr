# frozen_string_literal: true

# Runs the type check (`bin/steep check`) as CI does: it prints Steep's
# output, and fails if Steep finds an error or if a Steep worker stops on
# an exception. A worker that stops leaves its file unchecked and Steep
# still exits 0, so the check looks for the FATAL line that the worker
# logs. The first check has the compiler and this host's kernel layers;
# then the `kernel` target checks each other layer (Steepfile, KERNEL_LAYERS).
#
#   ruby .github/scripts/steep.rb [STEEP CHECK OPTIONS...]

require "open3"

root = File.expand_path("../..", __dir__)
host = RUBY_PLATFORM.include?("darwin") ? "darwin" : "linux"
checks = [[{}, []]] + (%w[darwin linux wasi] - [host]).map { |os| [{ "ZR_KERNEL_OS" => os }, ["--group=kernel"]] }

failed = checks.reject do |env, options|
  output, status = Open3.capture2e(env, File.join(root, "bin/steep"), "check", "--no-daemon", *options, *ARGV, chdir: root)
  print output

  crashed = output.lines.grep(/\bFATAL\b/)
  warn "steep: a worker stopped, and its file is not checked:\n#{crashed.join}" unless crashed.empty?
  status.success? && crashed.empty?
end
exit(failed.empty? ? 0 : 1)
