# frozen_string_literal: true

# md5init.c, in ruby: Digest::MD5 over the kernel's compression.
require "digest"

module Digest
  class MD5 < Base
    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, 0, 0, 16, 64, true))
  end
end
