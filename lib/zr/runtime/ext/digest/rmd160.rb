# frozen_string_literal: true

# Derived from CRuby's ext/digest (each algorithm's own license, and Ruby or
# BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# rmd160init.c, in ruby: Digest::RMD160 over the kernel's compression.
require "digest"

module Digest
  class RMD160 < Base
    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, 4, 5, 20, 64, true))
  end
end
