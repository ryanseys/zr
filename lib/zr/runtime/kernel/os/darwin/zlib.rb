# Derived from zlib 1.3.1 (Zlib); see THIRD_PARTY_NOTICES.md.

module Zr::Kern
  # The operating system byte in a gzip header: zutil.h's OS_CODE. It is 19
  # for a build on macOS, the same as ruby's zlib on this system.
  #: () -> word
  def zr_zlib_os_code
    19
  end
end
