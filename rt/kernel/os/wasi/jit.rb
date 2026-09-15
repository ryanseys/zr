# WASI's half of loading code: a module can map no code and look up no
# symbol, so eval's JIT has nothing to write into.
RTLD_DEFAULT = 0

sig [Value, Value, Value] => Value
machine def zr_os_jit_map(size, exec, hint)
  Machine.value(QNIL)
end

sig [Value] => Value
machine def zr_os_symbol(name)
  Machine.value(QNIL)
end

sig [Value, Value] => Value
machine def zr_os_jit_write(at, bytes)
  zr_notimplement(Machine.bytes("mmap"), 4)
end

# No library is loaded into a module.
sig [] => Ptr
machine def zr_os_libffi_path
  Machine.bytes("\0")
end
