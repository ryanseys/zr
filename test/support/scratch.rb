# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Zr
  module Test
    # The directories the tiers make under the system's temporary one.
    # Each is removed by whoever made it -- a block's end, the tier's
    # `at_exit` -- but a tier that is killed runs neither, and a
    # directory a pool worker made outlives it, since a worker ends in
    # `exit!`. They were 35 GB on 2026-09-23. `mktmpdir` spells its
    # maker's pid into the name (`zr-bins-20260923-4711-x1y2z3`), and
    # no process uses a directory whose maker is gone, so a tier sweeps
    # those as it starts. A pid that is alive keeps its directory, even
    # when the system has handed the number to someone else: a sweep
    # may leave a directory too many, never take one in use.
    module Scratch
      PATTERN = /\Azr-.+?-\d{8}-(\d+)-/

      module_function

      def sweep(root = Dir.tmpdir)
        Dir.children(root).each do |name|
          pid = name[PATTERN, 1] or next
          FileUtils.rm_rf(File.join(root, name)) unless alive?(Integer(pid))
        end
      rescue SystemCallError
        nil # a sweep is housekeeping; a tier does not fail for it
      end

      def alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true # someone else's process
      end
    end
  end
end
