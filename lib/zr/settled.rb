# frozen_string_literal: true

module Zr
  # A build whose sources changed during the build stops before it
  # caches anything. Its output came from a mix of the bytes that the
  # digest covers and the new bytes on disk, and no cache key describes
  # that mix.
  class SourceChanged < StandardError; end

  # A source file that changed after a runtime's digest was computed,
  # or nil (`Runtime#moved`). `Zr.runtime` keeps each runtime of this
  # process in `@runtimes`.
  def self.moved
    (@runtimes || {}).each_value.filter_map(&:moved).first
  end

  # Raises SourceChanged if a source moved. Each cache write calls this
  # first.
  def self.settled!
    file = moved
    raise SourceChanged, "#{file} changed while this build ran; nothing it built is kept -- run it again" if file
  end
end
