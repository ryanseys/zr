# frozen_string_literal: true

# Runs the type check (`bin/steep check`) as CI does: it prints Steep's
# output, and fails if Steep finds an error or if a Steep worker stops on
# an exception. A worker that stops leaves its file unchecked and Steep
# still exits 0, so the check looks for the FATAL line that the worker
# logs.
#
#   ruby .github/scripts/steep.rb [STEEP CHECK OPTIONS...]

require "open3"

root = File.expand_path("../..", __dir__)
output, status = Open3.capture2e(File.join(root, "bin/steep"), "check", "--no-daemon", *ARGV, chdir: root)
print output

crashed = output.lines.grep(/\bFATAL\b/)
abort "steep: a worker stopped, and its file is not checked:\n#{crashed.join}" unless crashed.empty?
exit status.exitstatus || 1
