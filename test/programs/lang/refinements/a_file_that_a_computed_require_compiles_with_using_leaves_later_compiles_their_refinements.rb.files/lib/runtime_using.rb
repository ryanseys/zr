module RuntimeDClone
  refine Object do
    def runtime_dclone = [:cloned, self]
  end
end
using RuntimeDClone
p 1.runtime_dclone
