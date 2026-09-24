# frozen_string_literal: true

module Zr
  module Test
    # What a target other than the host can fail, and why:
    # `test/baselines/<triple>.txt`. Each line is a key and a reason,
    # separated by a tab. A key is an end-to-end program
    # (`e2e/core/io/file_io_roundtrip.rb`) or a spec example (its file
    # below `test/` and its description, separated by `: `). A `#` line
    # is a comment.
    #
    # A listed test that fails is a skip that gives the reason. A listed
    # test that passes fails the run, so the file stays current.
    module Baseline
      DIR = File.expand_path("../baselines", __dir__)

      module_function

      def path(target) = File.join(DIR, "#{target.triple}.txt")

      def for(target)
        file = path(target)
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
