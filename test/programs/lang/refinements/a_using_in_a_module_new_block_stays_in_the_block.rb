# A `using` in a block that runs with a cref of its own (Module.new,
# class_eval and the like) refines that block alone, not the rest of the file.
refinery = Module.new do
  refine Array do
    def deconstruct = [0]
  end
end

result = nil
Module.new do
  using refinery
  result = case []
           in [0] then :refined
           end
end
p result

Class.new.class_eval do
  using refinery
  p([].deconstruct)
end

[1, 2] => a, b
p [a, b]
p(([3] in [^(1 + 2)]))
p((1 in 1))
p [].respond_to?(:deconstruct)
