# Derived from zlib 1.3.1 (Zlib); see THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # The operating system byte in a gzip header: zutil.h's OS_CODE. It is 3
  # (Unix) for a build on Linux.
  #: () -> word
  def zr_zlib_os_code
    3
  end
end
