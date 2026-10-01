# frozen_string_literal: true

require_relative "../command"

module Zr
  module CLI
    module Commands
      # `zr targets`: a table of each target, the outputs zr makes for it,
      # and the outputs that this host can make.
      class Targets < Command
        def plain? = true

        def run(_argv)
          label = ->(output) { output == :native ? "binary" : output.to_s }
          rows = Target.all.map do |target|
            here = target.outputs.select { |output| target.refusal(output == :native ? nil : output.to_s).nil? }
            [target.triple, target.outputs.map(&label).join(", "), here.empty? ? "none" : here.map(&label).join(", ")]
          end
          [["TARGET", "OUTPUTS", "ON THIS HOST"], *rows].each do |row|
            puts format("%-22s %-18s %s", *row).rstrip
          end
        end
      end
    end
  end
end
