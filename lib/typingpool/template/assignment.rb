module Typingpool
  class Template

    #A Template::Assignment works just like a regular template, except
    #that within each transcript dir (Config#transcript and the
    #built-in app template dir) we search within a subdir called
    #'assignment' first, then, after all the 'assignment' subdirs have
    #been search, we look in the original template dirs.
    class Assignment < Template
      def self.look_in_from_config(*args)
        look_in = super(*args)
        look_in.unshift(look_in.reject{|dir| dir.empty? }.map{|dir| File.join(dir, 'assignment') })
        look_in.flatten
      end
    end #Assignment
  end #Template
end #Typingpool
