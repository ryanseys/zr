# Inherited class method whose body holds a local typed by a
# method that each subclass overrides. For each subclass, the local
# holds that subclass's object: Comment.find returns a Comment, not
# an Article. The real-blog app uses this shape.

class T_inherited_cmeth_self_returning_local_Base
  def self.find(id)
    result = adapter_find(id)
    result
  end
end

class T_inherited_cmeth_self_returning_local_Article < T_inherited_cmeth_self_returning_local_Base
  attr_accessor :id, :title
  def self.adapter_find(id)
    a = T_inherited_cmeth_self_returning_local_Article.new
    a.id = id
    a.title = "art-#{id}"
    a
  end
end

class T_inherited_cmeth_self_returning_local_Comment < T_inherited_cmeth_self_returning_local_Base
  attr_accessor :id, :body
  def self.adapter_find(id)
    c = T_inherited_cmeth_self_returning_local_Comment.new
    c.id = id
    c.body = "comment-#{id}"
    c
  end
end

a = T_inherited_cmeth_self_returning_local_Article.find(7)
puts a.title
c = T_inherited_cmeth_self_returning_local_Comment.find(9)
puts c.body
