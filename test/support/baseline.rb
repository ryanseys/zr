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
    module Baseline
      DIR = File.expand_path("../baselines", __dir__)

      module_function

      def path(target) = File.join(DIR, "#{target.triple}.txt")

      # The baseline of another project's program tests (`bin/test
      # --corpus DIR`): `corpus/<project>-<triple>.txt`, whose keys are the
      # programs' paths below DIR. The project is the directory above DIR,
      # so spinel's `test/` has `corpus/spinel-<triple>.txt`.
      def corpus(root, target)
        read(File.join(DIR, "corpus", "#{File.basename(File.dirname(File.expand_path(root)))}-#{target.triple}.txt"))
      end

      def for(target) = read(path(target))

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
