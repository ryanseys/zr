# A user class that defines `index` does not take a call to `index` on
# a receiver of unknown type.

class ArticlesController
  def index
    "controller-action"
  end
end

# A param with no caller. No code calls `find_first`, so the program only
# has to compile and run. (Integer#index does not exist in CRuby.)
def find_first(raw_key)
  raw_key.index("[")
end

puts "compiled-cleanly"
