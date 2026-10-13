# A block that another thread or fiber runs keeps the node where its def
# was found, so its super goes on from there, also when the module is in
# the ancestors twice.
module M
  def m
    [:M, *Thread.new { super }.value]
  end
end
class C
  prepend M
  def m = :C
end
class SC < C
  prepend M
  def m = [:SC, *super]
end
p SC.new.m
module N
  def m
    [:N, *Fiber.new { super }.resume]
  end
end
class E; prepend N; def m = :E; end
class F < E; prepend N; def m = [:F, *super]; end
p F.new.m
module K
  def k = [:K, Thread.new { defined?(super) }.value, *Thread.new { Thread.new { super }.value }.value]
end
class G; prepend K; def k = [:G]; end
class H < G; prepend K; def k = [:H, *super]; end
p H.new.k
