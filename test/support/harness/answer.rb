# frozen_string_literal: true

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

      # A text that tells how `other` is different from this output.
      def apart_from(other)
        out = []
        %i[stdout stderr].each do |what|
          want, got = public_send(what).lines, other.public_send(what).lines
          next if want == got

          n = want.zip(got).index { |a, b| a != b }
          out << if n && n < [want.size, got.size].min
                   "#{what}: want #{want[n].chomp.inspect}, got #{got[n].chomp.inspect}"
                 else
                   "#{what}: want #{want.size} line(s), got #{got.size} -- #{(want[got.size] || got[want.size]).to_s.chomp.inspect}"
                 end
        end
        out << "#{status} vs #{other.status}" if status != other.status
        out.empty? ? "identical text, unequal bytes" : out.join("\n           ")
      end
    end
  end
end
