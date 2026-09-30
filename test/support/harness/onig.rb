# frozen_string_literal: true

require_relative "../../../lib/zr/runtime_sources"

module Zr
  module Harness
    # Regexp::Onig, zr's regular expression compiler (runtime/core/regexp),
    # loaded under the host ruby, for the tests and tools that check it
    # against ruby's own engine. zr compiles these files into a program's
    # core; ruby loads them here as ordinary Ruby.
    module Onig
      def self.load! = RuntimeSources::ONIG_NAMES.each { |name| require File.join(Paths::RUNTIME, "core/#{name}.rb") }
    end
  end
end
