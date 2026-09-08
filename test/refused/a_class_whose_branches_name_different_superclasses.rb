# a class whose branches name different superclasses
if [].any?
  class Vm < String
    def which = :one
  end
else
  class Vm < Array
    def which = :two
  end
end
