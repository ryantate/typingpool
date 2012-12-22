module Typingpool
  class Amazon
    class HIT
      class Assignment
        require 'typingpool/amazon/hit/assignment/empty'

        #See the RTurk documentation and Amazon Mechanical Turk API
        #documentation for more on these fields.
        attr_reader :id, :status, :worker_id, :submitted_at

        #Constructor. Takes an RTurk::Hit instance.
        def initialize(rturk_hit)
          if assignment = rturk_hit.assignments[0] #expensive!
            @id = assignment.id
            @status = assignment.status
            @worker_id = assignment.worker_id
            @submitted_at = assignment.submitted_at
            if answers = assignment.answers
              @answers = answers.to_hash
            end
          end
        end

        #Returns the answers associated with this assignment as a
        #hash. If there are no answers, returns an empty hash.
        def answers
          @answers ||= {}
        end

        #Returns the transcription submitted by the user as raw text.
        def body
          (answers['transcription'] || answers['1']).to_s
        end

        #Returms an RTurk::Assignment object corresponding to this
        #assignment.
        def at_amazon
          RTurk::Assignment.new(@id)
        end
      end #Assignment
    end #HIT
  end #Amazon
end #Typingpool
