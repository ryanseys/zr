# `private` (bare, `private def`, and `private :name`) inside a
# compiled `class << obj` body must mark the method PRIVATE on the
# object, the same as it would on a class. A fresh `def` after that
# resets to the running default. `clone` carries the singleton table,
# and the visibility marks with it; `dup` does not carry the
# singleton table at all. A non-object heap value (for example, a
# String) keeps its own singleton table, and the marks must follow it
# there too.
#
# The three spellings are one cause and are pinned together here.

def try(label)
  p [label, yield]
rescue NoMethodError, NameError => e
  p [label, :raised, e.class.to_s]
end

o = Object.new
class << o
  def pub = :pub
  private
  def cursor = :cursor
  protected
  def prot = :prot
end
try(:cursor_public) { o.public_send(:cursor) }
try(:cursor_send)   { o.send(:cursor) }
try(:prot_public)   { o.public_send(:prot) }
try(:pub_public)    { o.public_send(:pub) }
try(:singletons)    { o.singleton_methods.sort }
try(:privates)      { o.private_methods(false).include?(:cursor) }
try(:protecteds)    { o.protected_methods(false) }

o2 = Object.new
class << o2
  private def inline = :inline
  def open = :open
end
try(:inline_public) { o2.public_send(:inline) }
try(:inline_list)   { o2.singleton_methods.sort }

o3 = Object.new
class << o3
  def named = :named
  private :named
end
try(:named_public)  { o3.public_send(:named) }
try(:named_list)    { o3.singleton_methods }

# A fresh `def` resets the name to the running default, on an object exactly
# as on a class.
o4 = Object.new
class << o4
  private
  def reset = :first
end
def o4.reset = :second
try(:reset_public)  { o4.public_send(:reset) }
try(:reset_list)    { o4.singleton_methods }

# `clone` carries the singleton table, so it carries the marks with it.
o5 = Object.new
class << o5
  private
  def carried = :carried
end
try(:clone_public)  { o5.clone.public_send(:carried) }
try(:clone_list)    { o5.clone.singleton_methods }
try(:dup_list)      { o5.dup.singleton_methods }

# A non-object heap value keeps its rows in a table of its own, and the mark
# has to follow them there.
s = +"str"
class << s
  private
  def shout = :shout
end
try(:value_public)  { s.public_send(:shout) }
try(:value_list)    { s.singleton_methods }
