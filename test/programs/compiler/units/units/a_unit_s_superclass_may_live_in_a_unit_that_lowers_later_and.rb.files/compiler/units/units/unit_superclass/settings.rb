# An unrelated namespace with its own `Path`. A `class X < Path` in
# another scope must not resolve to this one.
module Settings
  Path = Struct.new(:explicit, :system) do
    def kind = "struct"
  end
end
