# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # Tools that make large edits to spec files safe.
    #
    #   zr-dev spec verify HEAD                    what changed since a revision
    #   zr-dev spec verify HEAD --renames          ... and permit changed sentences
    #   zr-dev spec verify HEAD~3 test/spec/core   ... in one area
    #   zr-dev spec fingerprint                    a digest for each example, to diff yourself
    #   zr-dev spec check                          the formatting conventions
    #   zr-dev spec tidy                           fix the safe faults that check reports
    #
    # `Zr::Reader` reads a spec file without compiling or running anything.
    # It returns the parts of each example: its sentence, its program, its
    # keywords, and its expected output. If two files give the same parts,
    # they have the same meaning. The full suite fingerprints in seconds.
    #
    # Limits: the reader does not see anything outside an example (file
    # comments, `require` lines, blank lines). It reads a guard (`only:`)
    # against this host only. Thus it shows that the meaning is the same,
    # not that the file is the same. Use it with `zr-dev oracle`, which
    # checks each example against ruby.
    class Specs < Group
      summary "Check, tidy, verify, split or grow the spec files"

      commands({
        "check" => ["The formatting conventions", -> { require_relative "spec/check"; Check }],
        "tidy" => ["Fix what check reports that is safe to fix", -> { require_relative "spec/check"; Tidy }],
        "fingerprint" => ["A digest per example, to diff a rewrite against", -> { require_relative "spec/verify"; Fingerprint }],
        "verify" => ["What moved since a revision", -> { require_relative "spec/verify"; Verify }],
        "split" => ["Which bundled examples can be split, and into what", -> { require_relative "spec/split"; Split }],
        "ask" => ["What ruby answers for a candidate program, as an assertion", -> { require_relative "spec/ask"; Ask }],
        "dispatch" => ["Print the programs that show which methods a core class calls", -> { require_relative "spec/dispatch"; Dispatch }]
      })

      # A spec tool that reads the files under its paths, or test/spec.
      class Tool < Command
        usage "[path...]"

        def files(argv) = (argv.empty? ? ["test/spec"] : argv).flat_map { |path| Dev.spec_files(path) }
      end
    end
  end
end
