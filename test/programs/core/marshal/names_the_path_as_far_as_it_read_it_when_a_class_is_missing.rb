# `rb_path_to_class` walks the path from Object one component at a
# time, and a component that names nothing stops with the path as
# far as the walk read it -- which takes in the separator it had
# already stepped past. What the name does refer to is a second
# question, and a different error.
module Outer; end
class Real; end

def sym(name) = ":#{(name.bytesize + 5).chr}#{name}".b
def object(tag, name, rest = "") = "\x04\b#{tag}#{sym(name)}#{rest}".b
payload = Marshal.dump("payload")[2..]

[["d", "Absent", payload], ["d", "Absent::Nested", payload],
 ["d", "Outer::Nope", payload], ["d", "RUBY_VERSION", payload],
 ["d", "Outer", payload], ["o", "Absent", "\x00"], ["o", "Outer", "\x00"],
 ["e", "Absent", "0"], ["u", "Absent", "\a\x00\x00"], ["S", "Absent", "\x00"]].each do |tag, name, rest|
  begin
    p Marshal.load(object(tag, name, rest))
  rescue StandardError => e
    p [tag, name, e.class, e.message]
  end
end
