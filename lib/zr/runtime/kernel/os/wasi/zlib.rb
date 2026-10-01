module Zr::Kern
  # The operating system byte in a gzip header: zutil.h's OS_CODE. It is 3
  # (Unix) for a build that has no specific operating system code.
  sig [] => Word
  def zr_zlib_os_code
    3
  end
end
