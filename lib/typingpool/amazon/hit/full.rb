module Typingpool
  class Amazon
    class HIT
      class Full
        require 'uri'
        require 'open-uri'
        require 'nokogiri'
        require 'typingpool/amazon/hit/full/fromsearchhits'

        #See the RTurk documentation and Amazon Mechanical Turk API
        #documentation for more on these fields.
        attr_reader :id, :type_id, :status, :external_question_url, :assignments_completed, :assignments_pending, :expires_at, :assignments_duration

        #Constructor. Takes an RTurk::HIT instance.
        def initialize(rturk_hit)
          import_standard_attrs_from_rturk_hit(rturk_hit)
          @assignments_completed = rturk_hit.assignments_completed_count
          @assignments_pending = rturk_hit.assignments_pending_count
          self.annotation = rturk_hit.annotation
          self.external_question_url = rturk_hit.xml
        end

        #Returns the HIT annotation as a hash. If the annotation
        #contained URL-encoded form key-value pairs, it decodes them
        #and returns them as a hash. Otherwise, returns an empty hash
        #(throwing away any annotation text that is not URL-encoded
        #key-value pairs, for example the tags attached by the Amazon
        #Mechanical Turk RUI).
        def annotation
          @annotation ||= {}
        end

        #Returns boolean indicated whether the HIT is
        #expired. Determined by comparing the HIT's expires_at
        #attribute with the current time.
        def expired?
          expires_at < Time.now
        end

        #Returns boolean indicated whether the HIT is expired and
        #overdue, at which point it is totally safe to prune. This is
        #determined by adding the assignment duration (how long a
        #worker has to complete the HIT) to the HIT's expires_at time
        #(when the HIT is removed from the Mechanical Turk
        #marketplace).
        def expired_and_overdue?
          (expires_at + assignments_duration) < Time.now
        end

        #Returns the HTML of the external question associated with the
        #HIT. All Typingpool HITs use external questions (as opposed
        #to "internal" HIT QuestionForms), so this should always
        #return something. In first use, must make an HTTP request to
        #obtain the HTML.
        def external_question
          if @external_question.nil?
            if external_question_url && external_question_url.match(/^http/)
              #expensive, obviously:
              begin
                @external_question = open(external_question_url).read
              rescue OpenURI::HTTPError => e
                #we don't worry about missing questions because those
                #should only be attached to HITs that aren't ours. we
                #take both 403 and 404 to mean missing because S3
                #never returns 404, only 403.
                raise e unless e.message.match(/\b40[34]\b/)
              end #begin
            end #if external_question_url && external_question_url.match...
          end #if @external_question.nil?
          @external_question
        end

        #Takes the name of an HTML form param and returns the value
        #associated with that param in the external question
        #HTML. Triggers an HTTP request on first use (unless
        #external_question has already been called).
        def external_question_param(param)
          if external_question
            if input = Nokogiri::HTML::Document.parse(external_question).css("input[name=#{param}]")[0]
              return input['value']
            end
          end
        end

        protected

        def import_standard_attrs_from_rturk_hit(hit)
          %w(id type_id status expires_at assignments_duration).each do |attr|
            instance_variable_set("@#{attr}", hit.send(attr))
          end
        end

        def annotation=(encoded)
          @annotation = CGI.unescapeHTML(encoded.to_s)
          begin
            @annotation = URI.decode_www_form(@annotation) 
            @annotation = Hash[*@annotation.flatten]
          rescue ArgumentError
            #Handle annotations like Department:Transcription (from
            #the Amazon RUI), which make URI.decode_www_form barf
            @annotation = {}
          end
        end

        def external_question_url=(noko_xml)
          if node = noko_xml.css('HIT Question eq|ExternalQuestion eq|ExternalURL', {'eq' => 'http://mechanicalturk.amazonaws.com/AWSMechanicalTurkDataSchemas/2006-07-14/ExternalQuestion.xsd'})[0]
            if url = node.inner_text
              @external_question_url = url
            end
          end #if node =....
        end
      end #Full
    end #HIT
  end #Amazon
end #Typingpool
