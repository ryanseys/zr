# frozen_string_literal: true

require_relative "../gen"
require_relative "../../lib/zr/target"

module Zr
  module Dev
    module Commands
      class Gen
        # The table of targets in README.md and the table of how far CI
        # checks each one in docs/reference/targets.md, from `Target::ALL`
        # and `Target::SUPPORT`. Each table is the text between its two
        # marker lines; the rest of each file is written by hand.
        class Targets < Generator
          README = "README.md"
          DOC = "docs/reference/targets.md"
          BEGIN_MARK = "<!-- targets: written by `zr-dev gen targets`. Do not edit. -->"
          END_MARK = "<!-- /targets -->"

          def run(_argv)
            [[README, readme_table], [DOC, doc_table]].map do |rel, table|
              text = File.read(Dev.path(rel))
              before, rest = text.split(BEGIN_MARK, 2)
              _, after = rest&.split(END_MARK, 2)
              fail!("#{rel}: no #{BEGIN_MARK} ... #{END_MARK} lines") unless before && after

              Dev.write(rel, check: check?) { |io| io.print(before, BEGIN_MARK, "\n", table, END_MARK, after) }
            end.all?
          end

          # What a build for `target` gives, and the host that can make it.
          def output(target)
            arch = target.arch.to_s
            case target.link
            when :darwin then ["native binary for macOS #{target.min_os.to_i} or later (Apple Silicon)", "any host"]
            when :static then ["static binary for any #{arch} Linux", "#{arch} Linux with musl's `cc`, or a host with a musl cross toolchain"]
            when :dynamic
              ["dynamic binary for #{arch} Linux with glibc 2.35 or later", "#{arch} glibc Linux with `cc`, or a host with `#{target.triple}-gcc`"]
            else ["WASI module", "any host"]
            end
          end

          def readme_table
            rows = Target.all.map do |target|
              what, host = output(target)
              "| `#{target.triple}` | #{what} | #{host} | #{target.support} |\n"
            end
            "| Target | Output | Built on | Status |\n|---|---|---|---|\n#{rows.join}"
          end

          def doc_table
            rows = Target.all.map do |target|
              says = target.support == :tested ? "its program tests run in CI" : "CI builds it and runs a slice of the program tests"
              "| `#{target.triple}` | #{target.support} | #{says} |\n"
            end
            "| Target | Status | What CI checks |\n|---|---|---|\n#{rows.join}"
          end
        end
      end
    end
  end
end
