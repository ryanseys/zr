# `Kernel.<m>` calls the Kernel module function, the same as a bare
# `<m>(...)`. Users write it when a `def self.<m>` shadows the
# Kernel method.

class T_kernel_module_function_call_Sched
  def self.nap(seconds)
    # Kernel-prefixed to disambiguate from a hypothetical
    # def self.sleep on the same class.
    Kernel.sleep(seconds)
    0
  end
end

T_kernel_module_function_call_Sched.nap(0)
puts "ok"
