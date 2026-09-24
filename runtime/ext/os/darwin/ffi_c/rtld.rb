# frozen_string_literal: true

# darwin's dlopen(3) flags, as FFI::DynamicLibrary names them.
module FFI
  class DynamicLibrary
    RTLD_LAZY = 0x1
    RTLD_NOW = 0x2
    RTLD_GLOBAL = 0x8
    RTLD_LOCAL = 0x4
    RTLD_NOLOAD = 0x10
    RTLD_NODELETE = 0x80
    RTLD_FIRST = 0x100
    RTLD_DEEPBIND = 0
    RTLD_MEMBER = 0
    RTLD_BINDING_MASK = 0x3
    RTLD_LOCATION_MASK = 0xc
    RTLD_ALL_MASK = 0x19f
  end
end
