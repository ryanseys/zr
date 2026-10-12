# frozen_string_literal: true

module Zr
  module Test
    # What a target can fail, and why: `test/baselines/<triple>.txt`. Each
    # line is a key and a reason, separated by a tab. A key is a program
    # test's path below test/programs (`cli/core/io/file_io_roundtrip.rb`).
    # A `#` line is a comment.
    #
    # A listed test that fails is a skip that gives the reason. A listed
    # test that passes fails the run, so the file stays current.
    #
    # `upgrade.txt` is the same for every target: the tests that a new ruby
    # (`.ruby-version`) changed and zr does not match yet. Each fix deletes
    # its line, and the upgrade is done when the file is gone.
    module Baseline
      DIR = File.expand_path("../baselines", __dir__)

      module_function

      def path(target) = File.join(DIR, "#{target.triple}.txt")

      def for(target) = upgrade.merge(read(path(target)))

      # What the host (`ZR_TEST_HOST=1`, CRuby over the kernel) can fail:
      # `host.txt`. A binary's own baseline does not apply there.
      def host = upgrade.merge(read(File.join(DIR, "host.txt")))

      # What a new ruby changed that zr does not match yet, on every target.
      def upgrade = read(File.join(DIR, "upgrade.txt"))

      def read(file)
        return {} unless File.file?(file)

        File.readlines(file, chomp: true).each_with_index.filter_map do |line, n|
          next if line.empty? || line.start_with?("#")

          key, why = line.split("\t", 2)
          raise ArgumentError, "#{file}: line #{n + 1}: a line is a key and a reason, separated by a tab" unless why

          [key, why]
        end.to_h
      end
    end
  end
end
