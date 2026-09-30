# A *rest splat method on a receiver that may be one of several user classes
# must collect the trailing call-site arguments into an Array, exactly like
# a call on a receiver of one known class.
class Rel
  def where(q, *args)
    "Rel[#{q}](#{args.inspect})"
  end
end
class Scope
  def where(q, *args)
    "Scope[#{q}](#{args.inspect})"
  end
end

[Rel.new, Scope.new].each do |o|
  puts o.where("id != ?")
  puts o.where("id != ?", 5)
  puts o.where("a = ? AND b = ?", 1, "two")
  puts o.where("mixed", :sym, 3.5, nil)
end
