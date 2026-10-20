# frozen_string_literal: true

module Zr
  # Marks each error of a build that the caller can fix: a refused program
  # or target, a bad setting, a gem that does not resolve, a cache that is
  # not the user's. `rescue Zr::Error` catches them all (`Zr.build`); any
  # other error is a defect in zr.
  # @rbs module-self: Exception
  module Error; end

  # This host cannot build or run for the target, or zr does not run on
  # this ruby or this OS.
  class TargetRefused < StandardError
    include Error
  end

  # The program does not parse, or ruby's compiler rejects it. `file` and
  # `line` say where, when the parse knows it.
  class InvalidProgram < StandardError
    include Error

    attr_reader :file #: String?
    attr_reader :line #: Integer?

    #: (String message, ?file: String?, ?line: Integer?) -> void
    def initialize(message, file: nil, line: nil)
      super(message)
      @file = file
      @line = line
    end
  end

  # A step after the program's check stopped: a backend that cannot
  # compile the code, or a link or a write that failed. The message says why.
  class BuildError < StandardError
    include Error
  end
end
