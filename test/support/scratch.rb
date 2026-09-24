# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Zr
  module Test
    # Removes old directories that the tiers make in the system temporary
    # directory. Usually the maker removes each one (at the end of a
    # block, or in `at_exit`). A killed tier does not, and a pool worker
    # ends in `exit!`, so its directories stay. These can grow to tens of
    # GB. `mktmpdir` puts the pid of its maker in the name
    # (`zr-bins-20260923-4711-x1y2z3`). When that process is gone, no
    # process uses the directory, so a tier removes it when it starts. A
    # live pid keeps its directory, even if the system gave the pid to a
    # different process: a sweep can leave extra directories, but it
    # never removes one in use.
    module Scratch
      PATTERN = /\Azr-.+?-\d{8}-(\d+)-/

      module_function

      def sweep(root = Dir.tmpdir)
        Dir.children(root).each do |name|
          pid = name[PATTERN, 1] or next
          FileUtils.rm_rf(File.join(root, name)) unless alive?(Integer(pid))
        end
      rescue SystemCallError
        nil # the sweep is only cleanup; a tier does not fail because of it
      end

      def alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true # a process of a different user
      end
    end
  end
end
