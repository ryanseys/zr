# A method compiled but never called whose body splits an unresolvable chain
# (`Undefined.application.class.to_s.split("::")`) must not stop the program.
# The method never runs, so the unresolved constant never raises.
class T
  def initialize(s)
    @s = s
  end
  def name
    @s[:name] || fallback
  end
  def fallback
    Undefined.application.class.to_s.split("::").first
  end
end

puts T.new({ name: "ok" }).name
