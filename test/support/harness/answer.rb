# frozen_string_literal: true

require_relative "../../../lib/zr/diff"

module Zr
  module Harness
    # The output of a program: stdout, stderr, exit status and signal.
    Answer = Struct.new(:stdout, :stderr, :code, :signal) do
      def status
        signal ? "signal #{signal}" : "exit #{code}"
      end

      # The recording of ruby's output for the program at `path`. It is
      # read from the files next to the program: always `<name>.out`, and
      # `<name>.err`, `<name>.status` and `<name>.signal` when they are
      # not empty. Each file contains only the raw bytes, so there is
      # nothing to parse or unescape. `zr-dev record` writes these files for a
      # benchmark.
      # Returns nil when there is no recording.
      def self.beside(path)
        base = path.delete_suffix(".rb")
        return nil unless File.file?("#{base}.out")

        part = ->(kind) { File.file?("#{base}.#{kind}") ? File.binread("#{base}.#{kind}") : nil }
        new(File.binread("#{base}.out"), part.call("err") || +"".b,
            Integer(part.call("status") || 0), part.call("signal")&.then { |n| Integer(n) })
      end

      # A text that tells how `other` is different from this output: the
      # first line that differs in stdout and in stderr, and the status.
      def apart_from(other)
        out = %i[stdout stderr].filter_map do |what|
          want = public_send(what).lines
          got = other.public_send(what).lines
          change = Zr::Diff.first_change(want, got) or next
          _, a, b = change
          if a && b
            "#{what}: want #{a.chomp.inspect}, got #{b.chomp.inspect}"
          else
            "#{what}: want #{want.size} line(s), got #{got.size} -- #{(a || b).to_s.chomp.inspect}"
          end
        end
        out << "#{status} vs #{other.status}" if status != other.status
        out.empty? ? "identical text, unequal bytes" : out.join("\n           ")
      end

      # A unified diff of stderr and of stdout for each that differs from
      # `got`, then the status when it differs.
      def diff(got)
        out = %i[stderr stdout].filter_map do |part|
          a = public_send(part).b
          b = got.public_send(part).b
          "--- expected #{part}\n+++ actual #{part}\n#{Zr::Diff.unified(a, b)}" unless a == b
        end
        out << "status: expected #{status}, actual #{got.status}" if status != got.status
        out.join("\n")
      end
    end
  end
end
