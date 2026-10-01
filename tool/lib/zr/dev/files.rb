# frozen_string_literal: true

require "stringio"

module Zr
  module Dev
    # Writes a generated file in one step. The block prints into a
    # String, and the file changes only when the block completes: a
    # generator that stops leaves the old file. With `check`, nothing is
    # written, and the result is false when the file is out of date.
    # Returns true when the file is (or now is) current.
    def self.write(rel, check: false)
      io = StringIO.new
      yield io
      if rel.start_with?("lib/zr/runtime/kernel/")
        require_relative "../../../kern_rewrite"
        io = StringIO.new(KernRewrite.rewrite(io.string, KernRewrite.imports))
      end
      path = self.path(rel)
      current = File.file?(path) && File.binread(path) == io.string.b
      if check
        warn(current ? "#{rel}: current" : "#{rel}: out of date; `zr-dev gen` writes it")
        return current
      end

      Paths.write_atomic(path, io.string) unless current
      warn "#{current ? "kept" : "wrote"} #{rel} (#{io.string.lines.size} lines)"
      true
    end
  end
end
