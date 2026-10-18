module Zr::Kern
  # RUBY_PLATFORM, as ruby built against musl gives it.
  #: () -> value
  def zr_os_ruby_platform
    zr_str_new(Machine.bytes("x86_64-linux-musl"), 17)
  end
end
