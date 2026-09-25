# frozen_string_literal: true

require_relative "../spec"
require_relative "../oracle"

module Zr
  module Dev
    class Specs
      # Finds bundled examples that can be split into smaller examples.
      #
      # Some examples contain `# === <name> ===` banners. Each banner starts
      # a section that is a separate test. One `must_answer` covers all the
      # sections, so a failure gives one large diff, and the example name
      # does not identify the section.
      #
      # A section is safe to split out only if it does not depend on the
      # sections before it. Each `t_<name>` is called immediately after its
      # definition, so the output of a section is a contiguous part of the
      # bundle's output. The tool runs each section separately. If the
      # joined outputs equal the bundle's output, the sections are
      # independent. If not, the tool leaves the bundle as it is.
      class Split < Tool
        summary "Which bundled examples can be split, and into what"
        host_ruby!

        BANNER = /^# === (.+) ===$/
        MANIFEST = /\A# Bundled tests:\n(?:#(?:   .*)?\n)*/

        def run(argv)
          Dev.reader!
          splittable = coupled = gained = 0
          files(argv).each do |file|
            Reader.read(file).each do |e|
              head, parts = sections(e.source)
              next unless parts

              answers = parts.map { |_, body| ask(e, "#{head}\n\n#{body}") }
              joined = answers.map { |a| a&.stdout.to_s }.join
              if answers.any?(&:nil?) || joined != e.want[:stdout].to_s
                coupled += 1
                warn "#{Dev.rel(file)}: #{e.name}: sections interact, left whole"
                next
              end

              splittable += 1
              gained += parts.size - 1
              puts format("%-52s %-22s %d section(s)", Dev.rel(file), e.name, parts.size)
            end
          end
          puts format("%d example(s) split cleanly into %d, %d left whole", splittable, splittable + gained, coupled)
        end

        # `[preamble, [[name, body], ...]]`, or nil when there are no banners.
        def sections(source)
          return nil unless source&.match?(BANNER)

          head, *rest = source.split(BANNER)
          return nil if rest.empty?

          [head.sub(MANIFEST, "").strip, rest.each_slice(2).map { |name, body| [name.strip, body.to_s] }]
        end

        # Runs one candidate program with ruby as `zr-dev oracle` does, so
        # that the normalization and the environment are the same.
        def ask(example, source)
          probe = example.dup
          probe.source = source
          Oracle.answer(probe)
        end
      end
    end
  end
end
