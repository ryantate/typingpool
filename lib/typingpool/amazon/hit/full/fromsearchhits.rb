module Typingpool
  class Amazon
    class HIT
      class Full

        #For more on why this subclass is neccesary, see the
        #documentation for
        #Typingpool::Amazon::HIT.cached_or_new_from_searchhits. In
        #short, RTurk::HITParser objects returned by RTurk::SearchHITs
        #are pointlessly and subtly different from
        #RTurk::GetHITResponse objects. (I need to submit a patch to
        #RTurk.)
        class FromSearchHITs < Full
          #Constructor. Takes an RTurk::Hit instance and the text of
          #the HIT's annotation. The text of the annotation must be
          #submitted as a separate param because RTurk::Hit instances
          #returned by RTurk::SearchHITs do not bother to extract the
          #annotation into an attribute, so we have to so that
          #ourselves (elsewhere) using the raw xml.
          def initialize(rturk_hit, annotation)
            import_standard_attrs_from_rturk_hit(rturk_hit)
            @assignments_completed = rturk_hit.completed_assignments
            @assignments_pending = rturk_hit.pending_assignments
            self.annotation = annotation
         end

          def external_question_url
            unless @checked_question
              self.external_question_url = at_amazon.xml
              @checked_question = true
            end
            @external_question_url
          end

          protected

          def at_amazon
            Amazon.rturk_hit_full(@id)
          end
        end #FromSearchHITs
      end #Full
    end #HIT
  end #Amazon
end #Typingpool
