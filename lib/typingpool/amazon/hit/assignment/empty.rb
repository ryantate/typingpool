module Typingpool
  class Amazon
    class HIT
      class Assignment

        #Subclass used in cases where we know Amazon's servers have no
        #assignments for us (because hit.full.assignments_completed ==
        #0), so we don't want to bother doing an HTTP request to
        #check.
        class Empty < Assignment
          def initialize
            @answers = {}
          end

        end #Empty
      end #Assignment
    end #HIT
  end #Amazon
end #Typingpool
