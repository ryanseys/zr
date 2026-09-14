# frozen_string_literal: true

# sha2init.c, in ruby: Digest::SHA256, SHA384 and SHA512 over the
# kernel's compression.
require "digest"

module Digest
  class SHA256 < Base
    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, 2, 2, 32, 64, false))
  end

  class SHA384 < Base
    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, 3, 4, 48, 128, false))
  end

  class SHA512 < Base
    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, 3, 3, 64, 128, false))
  end
end
