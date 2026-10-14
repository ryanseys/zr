# frozen_string_literal: true

require_relative "answer"

module Zr
  module Harness
    # Removes the parts of an output that change from run to run, so that
    # two outputs can be compared. It changes CRLF to LF, and the
    # program's absolute path to its path relative to the run directory.
    # It also removes the run directory and object addresses.
    module Normalize
      module_function

      # A process that a signal stopped has no exit status. Only the
      # signal counts.
      def answer(a, source, run_cwd)
        Answer.new(bytes(a.stdout, source, run_cwd), bytes(a.stderr, source, run_cwd), a.signal ? nil : a.code, a.signal)
      end

      def bytes(b, source, run_cwd)
        out = b.b.gsub("\r\n", "\n")
        abs = File.expand_path(source)
        cwd = File.expand_path(run_cwd)
        rel = abs.start_with?("#{cwd}/") ? abs.byteslice((cwd.bytesize + 1)..) : File.basename(abs)
        out = out.gsub(abs, rel)
        out = out.gsub("#{cwd}/", "")
        out.gsub(/0x[0-9a-f]+/) { |m| (8..16).cover?(m.bytesize - 2) ? "0xADDR" : m }
      end
    end
  end
end
