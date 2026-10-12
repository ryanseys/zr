# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # Programs that are mostly not valid Ruby: a seed cut, with bytes
      # removed or added, or with lines swapped, as the prism tests break
      # their cases (test/support/harness/prism_diff.rb). Ruby rejects
      # most of them with a SyntaxError, and zr must then print the same
      # report. A build must never stop with an internal error, a crash or
      # a hang (Classify::BUILD_FAULTS). A refusal is fine.
      module Junk
        # The bytes that go in: the ones that open, close or join forms.
        BYTES = "()[]{}|&*,.:;=<>?!@$#%'\"`\\/\n -+^~_1aZ".b

        module_function

        def break_up(source, rng)
          bytes = source.b
          at = bytes.empty? ? 0 : rng.rand(bytes.bytesize)
          out = case rng.rand(5)
                when 0 then bytes.byteslice(0, at)
                when 1 then bytes.byteslice(0, at) + bytes.byteslice([at + rng.rand(1..8), bytes.bytesize].min..)
                when 2 then bytes.byteslice(0, at) + BYTES.byteslice(rng.rand(BYTES.bytesize), 1) + bytes.byteslice(at..)
                when 3 then swap_lines(bytes, rng)
                else bytes.byteslice(0, at) + bytes.byteslice(rng.rand(bytes.bytesize + 1)..).to_s
                end
          out.force_encoding(Encoding::UTF_8)
        end

        def swap_lines(bytes, rng)
          lines = bytes.lines
          return bytes if lines.size < 2

          i = rng.rand(lines.size)
          j = rng.rand(lines.size)
          lines[i], lines[j] = lines[j], lines[i]
          lines.join
        end
      end

      # Junk made from the seed files.
      class JunkSource
        def initialize(files)
          @files = files
        end

        def next_candidate(rng)
          file = @files.sample(random: rng) or return nil
          Candidate.new(source: Junk.break_up(File.binread(file), rng), origin: "junk", meta: { file: Dev.rel(file) })
        end
      end
    end
  end
end
