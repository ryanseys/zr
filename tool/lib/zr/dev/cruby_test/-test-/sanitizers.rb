# frozen_string_literal: true

# A stand-in for CRuby's ext/-test-/sanitizers, a C extension that only
# CRuby's own tests load. zr builds no program with a sanitizer.
module Test
  class Sanitizers
    def self.asan_enabled? = false

    def self.lsan_enabled? = false
  end
end
