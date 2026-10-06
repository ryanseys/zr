# box.c defines Loader's three functions whether or not boxes are
# enabled; each passes the call on to Kernel's.
p Ruby::Box::Loader.singleton_methods.sort, Ruby::Box::Loader.private_instance_methods(false).sort
p Ruby::Box::Loader.require("set"), Ruby::Box::Loader.method(:load).arity
p Object.ancestors.include?(Ruby::Box::Loader)
