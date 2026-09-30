# `require_relative ".."` loads the parent directory's `<dir>.rb`. Ruby
# normalizes "views/articles/.." -> "views" and appends ".rb" -> "views.rb".
# It does not append ".rb" to a literal ".." to make "...rb". (Each view in
# roundhouse does `require_relative ".."` to load the views aggregator.)
require_relative "require_parent/views/articles/index"
