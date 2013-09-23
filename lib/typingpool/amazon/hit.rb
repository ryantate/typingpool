module Typingpool
  class Amazon
    #Class representing an Amazon Mechanical Turk Human Intelligence
    #Task (HIT).
    #
    #We go above and beyond RTurk::Hit for several practical reasons:
    # * To allow easy serialization.  Caching is a very useful way of
    #   reducing network calls to Amazon, and thus of speeding up
    #   Typingpool. RTurk::Hit objects cannot be dumped via Marshal,
    #   apparently due to some Nokogiri objects they
    #   contain. Typingpool::Amazon::HIT objects, in contrast, are
    #   designed to be easily and compactly serialized. They store the
    #   minimal subset of information we need via simple
    #   attribtues. (Presently we serialize via PStore.)
    # * To attach convenience methods. RTurk does not make it easy,
    #   for example, to get HITs beyond the first "page" returned by
    #   Amazon. This class provides methods that make it easy to get
    #   ALL HITs returned by various operations.
    # * To attach methods specific to Typingpool. For example, the url
    #   and project_id methods read params we've embedded in the
    #   annotation or in hidden fields on an external question, while
    #   the underlying stashed_params method optimizes its lookup of
    #   these variables based on how the app is most likely to be
    #   used. See also the ours? and cacheable? methods.
    # * To simplify. Typingpool HITs are constrained such that we can
    #   assume they all contain only one assignment and thus only a
    #   maximum of one answer. Also, once we've determined that a HIT
    #   does not belong to Typingpool, it is safe to cache it forever
    #   and never download it again from Amazon.
    # * To clearly partition methods that result in network
    #   calls. When you access an attribute under hit.full, like
    #   hit.full.status, it is clear you are doing something
    #   potentially expensive to obtain your hit status. Same thing
    #   with accessing an attribute under hit.assignment, like
    #   hit.assignment.worker_id -- it is clear an assignment object
    #   will need to be created, implying a network call. Calling
    #   hit.id, in contrast, is always fast. (Caveat: Accessing
    #   partitioned attributes often, but not always, results in a
    #   network call. In some cases, hit.full is generated at the same
    #   time we create the hit, since we've obtained a full HIT
    #   serialization from Amazon. In other cases, we only have a HIT
    #   id, so accessing anything under hit.full generates a network
    #   call.)
    class HIT
      require 'set'
      require 'uri'
      require 'typingpool/amazon/hit/full'
      require 'typingpool/amazon/hit/assignment'

      class << self

        #Constructor. Creates an Amazon Mechanical Turk HIT.
        #** Warning: This method can spend your money! **
        # ==== Params
        # [question]      Typingpool::Amazon::Question instance, used not
        #                 only to generate the (external) question but
        #                 also parsed to provide one or more core HIT
        #                 attributes. Must include a non-nil
        #                 annotation attribute. Provides fallback
        #                 values for HIT title and description.
        # [config_assign] The 'assign' attribute of a
        #                 Typingpool::Config instance (that is, a
        #                 Typingpool::Config::Root::Assign
        #                 instance). Must include values for reward,
        #                 lifetime, duration, and approval. May
        #                 include values for keywords and
        #                 qualifications. Preferred source for HIT
        #                 title and description. See
        #                 Typingpool::Config documentation for further
        #                 details.
        # ==== Returns
        # Typingpool::Amazon::HIT instance corresponding to the new
        # Mechanical Turk HIT.
        def create(question, config_assign)
          new(RTurk::Hit.create(:title => config_assign.title || question.title) do |hit|
                hit.description = config_assign.description || question.description
                hit.question(question.url)
                hit.annotation = question.annotation or raise Error, "Missing annotation from question"
                hit.reward = config_assign.reward or raise Error, "Missing reward config"
                hit.max_assignments = 1
                hit.lifetime = config_assign.lifetime or raise Error, "Missing lifetime config"
                hit.duration = config_assign.deadline or raise Error, "Missing deadline config"
                hit.auto_approval_delay = config_assign.approval or raise Error, "Missing approval config"
                hit.keywords = config_assign.keywords if config_assign.keywords
                config_assign.qualify.each{|q| hit.qualifications.add(*q.to_arg)} if config_assign.qualify
              end)
        end

        #Name of the hidden HTML form field used to provide the
        #project_id in an external question or (form-encoded)
        #annotation. Hard coded to typingpool_project_id but
        #overridable in a subclass.
        def id_at
          @@id_at ||= 'typingpool_project_id'
        end

        #Name of the hidden HTML form field used to provide the
        #(audio) url in an external question or (form-encoded)
        #annotation. Hard coded to typingpool_url but overridable in a
        #subclass.
        def url_at
          @@url_at ||= 'typingpool_url'
        end

        #Takes an array of HIT ids, returns Typingpool::Amazon::HIT
        #instances corresponding to those ids.
        def with_ids(ids)
          ids.map{|id| cached_or_new(RTurk::Hit.new(id)) }
        end

        #Returns all Typingpool HITs that have been approved, as an
        #array of Typingpool::Amazon::HIT instances.
        def all_approved
          hits = all_reviewable do |hit|
            begin
              #optimization: we assume it is more common to have an
              #unapproved HIT than an approved HIT that does not
              #belong to this app
              hit.approved? && hit.ours? 
            rescue RestClient::ServiceUnavailable => e
              warn "Warning: Service unavailable error, skipped HIT #{hit.id}. (Error: #{e})"
              false
            end
          end
          hits
        end

        #Returns as an array of Typingpool::Amazon::HIT instances all
        #HITs returned by Amazon's GetReviewableHITs operation (which
        #have HIT status == 'Reviewable'). Takes an optional filter
        #block (which should return true for HITs to be included in
        #the final results). If not supplied, will filter so the
        #returned hits are all Typingpool HITs (hit.ours? == true).
        def all_reviewable(&filter)
          hits = each_page do |page_number|
            RTurk.GetReviewableHITs(:page_number => page_number).hit_ids.map{|id| RTurk::Hit.new(id) }.map{|hit| cached_or_new(hit) }
          end
          filter_ours(hits, &filter)
        end

        #Takes a Typingpool::Project::Local#id and returns all HITs
        #associated with that project, as an array of
        #Typingpool::Amazon::HIT instances.
        def all_for_project(id)
          all{|hit| hit.ours? && hit.project_id == id}
        end

        #Returns all HITs associated with your AWS account as an array
        #of Typingpool::Amazon::HIT instances. Takes an optional
        #filter block (which should return true for HITs to be
        #included in the final results). If not supplied, will filter
        #so the returned hits are all Typingpool HITs (hit.ours? ==
        #true).
        def all(&filter)
          hits = each_page do |page_number|
            page = RTurk::SearchHITs.create(:page_number => page_number)
            raw_hits = page.xml.xpath('//HIT')
            page.hits.map do |rturk_hit|
              annotation = raw_hits.shift.xpath('RequesterAnnotation').inner_text.strip
              full = Amazon::HIT::Full::FromSearchHITs.new(rturk_hit, annotation)
              cached_or_new_from_searchhits(rturk_hit, annotation)
            end
          end
          filter_ours(hits, &filter)
        end

        #protected

        #Constructor. Takes an RTurk::Hit instance. Returns a
        #Typingpool::Amazon::HIT instance, preferably from the cache.
        def cached_or_new(rturk_hit)
          from_cache(rturk_hit.id) || new(rturk_hit)
        end

        #Constructor. Same as cached_or_new, but handles peculiarities
        #of objects returned by RTurk::SearchHITs. Such objects map
        #two Amazon HIT fields to different names than those used by
        #other RTurk HIT instances. They also do not bother to extract
        #the annotation from the Amazon HIT, so we have to do that
        #ourselves (elsewhere) and take it as a param here. Finally,
        #on the bright side, RTurk::SearchHITs already contain a big
        #chunk of hit.full attributes, potentially obviating the need
        #for an additional network call to flesh out the HIT, so this
        #method pre-fleshes-out the HIT.
        def cached_or_new_from_searchhits(rturk_hit, annotation)
          if not (typingpool_hit = from_cache(rturk_hit.id))
            typingpool_hit = new(rturk_hit)
            typingpool_hit.full(Amazon::HIT::Full::FromSearchHITs.new(rturk_hit, annotation))
          end
          typingpool_hit
        end

        def from_cache(hit_id, id_at=self.id_at, url_at=self.url_at)
          Amazon.cache.transaction do
            Amazon.cache[cache_key(hit_id, id_at, url_at)] 
          end
        end

        def delete_cache(hit_id, id_at=self.id_at, url_at=self.url_at)
          Amazon.cache.transaction do
            key = cache_key(hit_id, id_at, url_at)
            cached = Amazon.cache[key]
            Amazon.cache.delete(key) unless cached.nil?
          end
        end

        def cache_key(hit_id, id_at=self.id_at, url_at=self.url_at)
          "RESULT///#{hit_id}///#{url_at}///#{id_at}"
        end

        def each_page
          results = []
          page = 0
          begin
            page += 1
            new_results = yield(page)
            results.push(*new_results)
          end while new_results.count > 0
          results
        end

        def filter_ours(hits, &filter)
          filter ||= lambda{|hit| hit.ours? }
          hits.select do |hit| 
            selected = filter.call(hit)
            hit.to_cache
            selected
          end
        end
      end #class << self

      #Corresponds to the Amazon Mechanical Turk HIT#HITId
      attr_reader :id

      #Constructor. Takes an RTurk::Hit instance.
      def initialize(rturk_hit)
        @id = rturk_hit.id
      end

      #URL of the audio file associated with this HIT (the audio file
      #to be transcribed). Extracted from the annotation (when the HIT
      #was assigned via Typingpool) or from a hidden field in the HTML
      #form on the external question (when the HIT was assigned via
      #the Amazon Mechanical Turk RUI).
      def url
        @url ||= stashed_param(self.class.url_at)
      end

      #The Typingpool::Project::Local#id associated with this
      #HIT. Extracted as described for the url method.
      def project_id
        @project_id ||= stashed_param(self.class.id_at)
      end

      #Returns the Typingpool::Project#name associated with this HIT
      #by parsing the #url. May be dropped in a future release.
      def project_title_from_url(url=self.url)
        matches = Project.url_regex.match(url) or raise Error::Argument::Format, "Unexpected format to url '#{url}'"
        URI.unescape(matches[2])
      end

      #Returns true if this HIT has an approved assignment associated
      #with it. (Attached to Typingpool::Amazon::HIT rather than
      #Typingpool::Amazon::HIT::Assignment because sometimes we can
      #tell simply from looking at hit.full that there are no approved
      #assignments -- hit.full.assignments_completed == 0. This check
      #is only performed when hit.full has already been loaded.)
      def approved?
        assignment_status_match?('Approved')
      end

      #Returns true if this HIT has a rejected assignment associated
      #with it. (For an explanation of why this is not attached to
      #Typingpool::Amazon::HIT::Assignment, see the documentation for
      #approved?.)
      def rejected?
        assignment_status_match?('Rejected')
      end

      #Returns true if this HIT has a submitted assignment associated
      #with it. (For an explanation of why this is not attached to
      #Typingpool::Amazon::HIT::Assignment, see the documentation for
      #approved?.)
      def submitted?
        assignment_status_match?('Submitted')
      end


      #Returns true if this HIT is associated with Typingpool. One
      #Amazon account can be used for many tasks, so it's important to
      #check whether the HIT belongs to this software. (Presently,
      #this is determined by looking for a stashed param like url or
      #project_id).
      def ours?
        @ours ||= not(url.to_s.empty?)
      end

      #Returns a Typingpool::Transcript::Chunk instance built using
      #this HIT and its associated assignment.
      def transcript
        transcript = Transcript::Chunk.new(assignment.body)
        transcript.url = url
        transcript.project = project_id
        transcript.worker = assignment.worker_id
        transcript.hit = @id
        transcript
      end
      
      #If this HIT is cacheable, serializes it to the cache file
      #specified in the config passed to Amazon.setup, or specified in
      #the default config file. In short, a HIT is cacheable if it
      #does not belong to Typingpool (ours? == false), if it is
      #approved or rejected (approved? || rejected?), or if it is
      #expired (full.expired_and_overdue?). See also cacheable? code.
      #
      # When available, cached HITs are used by
      # Typingpool::Amazon::HIT.all,
      # Typingpool::Amazon::HIT.all_approved, and all the other class
      # methods that retrieve HITs. These methods call to_cache for
      # you at logical times (after downloading and filtering, when
      # the HIT is most fleshed out), so you should not need to call
      # this yourself. But if you have an operation that makes network
      # calls to further flesh out the HIT, calling to_cache may be
      # worthwhile.
      def to_cache
        #any obj containing a Nokogiri object cannot be stored in pstore - do
        #not forget this (again)
        if cacheable?
          Amazon.cache.transaction do
            Amazon.cache[self.class.cache_key(@id)] = self 
          end
        end
      end

      #Returns an RTurk::Hit instance corresponding to this HIT.
      def at_amazon
        Amazon.rturk_hit_full(@id)
      end
      
      #Deletes the HIT from Amazon's servers. Examines the HIT and
      #assignment status to determine whether calling the DisposeHIT
      #or DisableHIT operation is most appropriate. If the HIT has
      #been submitted but not approved or rejected, will raise an
      #exception of type
      #Typingpool::Error::Amazon::UnreviewedContent. Catch this
      #exception in your own code if you'd like to automatically
      #approve such HITs before removing them.
      def remove_from_amazon
        if full.status == 'Reviewable'
          if assignment.status == 'Submitted'
            raise Error::Amazon::UnreviewedContent, "There is an unreviewed submission for #{url}"
          end
          at_amazon.dispose!
        else
          at_amazon.disable!
        end
      end

      #Returns "the full hit" - a Typingpool::Amazon::HIT::Full
      #instance associated with this HIT. If the instance is being
      #created for the first time, this will trigger an HTTP request
      #to Amazon's servers. "Full" hit fields segregated because
      #accessing any one of them is expensive if we only have a hit id
      #(but after fetching one all are cheap). Accepts an optional
      #Typingpool::Amazon::HIT::Full (or subclass) to set for this
      #attribute, preventing the need to create one. This is useful in
      #cases in which extensive HIT data was returned by an Amazon
      #operation (for example, SearchHITs returns lots of HIT data)
      def full(full_hit=nil)
        if @full.nil?
          @full = full_hit || Full.new(at_amazon)
        end
        @full
      end

      #Returns the assignment associated with this HIT - a
      #Typingpool::Amazon::HIT::Assignment instance. The first time
      #this is called, an Amazon HTTP request is typically (but not
      #always) sent.
      def assignment
        if @assignment.nil?
          if @full && full.assignments_completed == 0
            #It would be dangerous to do this if the HIT were to be
            #cached, since we would then never check for the
            #assignment again. But we know this HIT won't be cached
            #while it is active, since we only cache approved and
            #rejected HITs.
            @assignment = Assignment::Empty.new
          else
            @assignment = Assignment.new(at_amazon) #expensive
          end
        end
        @assignment
      end


      #private

      def stashed_param(param)
        if @assignment && assignment.answers[param]
          return assignment.answers[param]
        elsif full.annotation[param]
          #A question assigned through this software. May be
          #expensive: May result in HTTP request to fetch HIT
          #fields. We choose to fetch (sometimes) the HIT rather than
          #the assignment on the assumption it will be MORE common to
          #encounter HITs with no answers and LESS common to encounter
          #HITs assigned through the RUI (and thus lacking in an
          #annotation from this software and thus rendering the HTTP
          #request to fetch the HIT fields pointless).
          return full.annotation[param]
        elsif full.assignments_completed.to_i >= 1
          #A question assigned through Amazon's RUI, with an answer
          #submitted. If the HIT belongs to this software, this
          #assignment's answers will include our param.  We prefer
          #fetching the assignment to fetching the external question
          #(as below) because fetching the assignment will potentially
          #save us an HTTP request down the line -- for example, if we
          #need other assignment data (e.g. assignment status).
          #Fetching the external question only serves to give us
          #access to params. If the answers do not include our param,
          #we know the HIT does not belong to this software, since we
          #know the param was also not in the annotation. So we are
          #safe returning nil in that case.
          return assignment.answers[param]
        else
          #A question assigned via Amazon's RUI, with no answer
          #submitted.  Expensive: Results in HTTP request to fetch
          #external question.
          return full.external_question_param(param)
        end
      end

      def assignment_status_match?(status)
        if @full
          return false if full.assignments_completed == 0
          return false if full.status != 'Reviewable'
        end
        assignment.status == status
      end


      @@cacheable_assignment_status = Set.new %w(Approved Rejected)
      def cacheable?
        if @ours == false
          return true
        end
        if @full
          return true if full.expired_and_overdue?
        end
        if @assignment && assignment.status
          return true if @@cacheable_assignment_status.include?(assignment.status)
        end
        return false
      end
    end #HIT
  end #Amazon
end #Typingpool
