# frozen_string_literal: true

# musl's dlopen(3) flags, with FFI::DynamicLibrary's names for them: the
# ones that musl does not have are 0, and ffi_c builds the masks from the rest.
module FFI
  class DynamicLibrary
    RTLD_LAZY = 0x1
    RTLD_NOW = 0x2
    RTLD_GLOBAL = 0x100
    RTLD_LOCAL = 0
    RTLD_NOLOAD = 0x4
    RTLD_NODELETE = 0x1000
    RTLD_FIRST = 0
    RTLD_DEEPBIND = 0
    RTLD_MEMBER = 0
    RTLD_BINDING_MASK = 0x3
    RTLD_LOCATION_MASK = 0x100
    RTLD_ALL_MASK = 0x1107
  end
end
