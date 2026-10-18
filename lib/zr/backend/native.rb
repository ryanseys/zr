# frozen_string_literal: true

require_relative "aarch64"
require_relative "x86_64"

module Zr
  module Backend
    module Native
      BY_ARCH = { aarch64: Aarch64, x86_64: X86_64 }.freeze #: Hash[Symbol, untyped]

      # The machine backend for `target`.
      #: (Target target) -> untyped
      def self.for(target) = BY_ARCH.fetch(target.arch) { raise ArgumentError, "no native backend for #{target}" }
    end
  end
end
