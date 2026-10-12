# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # Programs that the fuzzer did not write: the seeds of the mutator,
      # and the programs of `--mode seed`.
      module Corpus
        # A program test with one of these sidecars needs more than a plain
        # run (files, an environment, arguments, input), so it is no seed.
        SIDECARS = %w[.files .env .needs .args .stdin .ruby .gems .limits].freeze

        # The seed directories when none are given: zr's program tests and
        # the programs that the fuzzer kept.
        DEFAULT = [Dev.path("test/programs"), Dev.path("log/fuzz/corpus")].freeze

        module_function

        # Every seed file below `dirs` (or `dirs` themselves, when files):
        # Ruby files, and prism's fixtures (.txt), sorted.
        def files(dirs)
          dirs.flat_map do |dir|
            next [dir] if File.file?(dir)
            next [] unless File.directory?(dir)

            Dir.glob("**/*.{rb,txt}", base: dir).sort.map { |rel| File.join(dir, rel) }
          end.reject { |file| skip?(file) }
        end

        def skip?(file)
          return true if file.end_with?(".orig.rb", ".reduced.rb")
          return true if File.size(file) > 64 * 1024

          SIDECARS.any? { |side| File.exist?("#{file}#{side}") }
        end
      end

      # A program to check: its source, where it came from ("seed", "gen",
      # "mutate", "meta", "junk"), and what made it (a seed, a file, the
      # features of the generator), for the case record.
      Candidate = Struct.new(:source, :origin, :meta, keyword_init: true)

      # The programs of a list of files, one by one, in an order that the
      # seed decides.
      class SeedSource
        def initialize(files, rng)
          @files = files.shuffle(random: rng)
          @lock = Mutex.new
        end

        def size = @files.size

        def next_candidate(_rng)
          file = @lock.synchronize { @files.shift } or return nil
          Candidate.new(source: File.binread(file), origin: "seed", meta: { file: Dev.rel(file) })
        end
      end
    end
  end
end
