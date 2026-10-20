# frozen_string_literal: true

require_relative "error"

module Zr
  # A build whose sources changed during the build stops before it
  # caches anything. Its output came from a mix of the bytes that the
  # digest covers and the new bytes on disk, and no cache key describes
  # that mix.
  class SourceChanged < StandardError
    include Error
  end

  # The check each cache write makes first: that no source of this
  # process's runtimes (`Runtime.loaded`) changed since its digest.
  module SourceGuard
    module_function

    # A source file that changed after a runtime's digest was computed
    # (`Runtime#moved`), or nil. A process that loaded no runtime has none.
    def changed_file
      return nil unless Zr.const_defined?(:Runtime, false)

      Runtime.loaded.each_value.filter_map(&:moved).first
    end

    # Raises SourceChanged if a source moved.
    def check!
      file = changed_file
      raise SourceChanged, "#{file} changed while this build ran; nothing it built is kept -- run it again" if file
    end
  end
end
