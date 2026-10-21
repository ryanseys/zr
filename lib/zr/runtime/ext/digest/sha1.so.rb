# frozen_string_literal: true

# Derived from CRuby's ext/digest (each algorithm's own license, and Ruby or
# BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# sha1init.c, in ruby: Digest::SHA1 over the kernel's compression.
require "digest"

module Digest
  class SHA1 < Base
    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, 1, 1, 20, 64, false))
  end
end
