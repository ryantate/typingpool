module Typingpool
  class Amazon
    require 'rturk'
    require 'pstore'
    require 'typingpool/amazon/hit'
    require 'typingpool/amazon/question'

    @@cache_file = '~/.typingpool.cache'

    class << self

      #You must call Amazon.setup before using any subclass methods
      #that rely on Amazon servers.
      # ==== Params
      # Takes params as a hash of named arguments.
      #[:key]     Your Amazon Web Services Access Key ID. Required
      #           param. If not passed, will be read from :config.
      #[:secret]  Your Amazon Web Services Secret Access Key. Required
      #           param. If not passed, will be read from :config.
      #[:config]  A Typingpool::Config instance. If not passed, will
      #           use the default Config.file (usually
      #           ~/.typingpool). Supplies the default values for :key
      #           and :secret and can override the default cache file
      #           location (usually ~/.typingpool.cache) via the
      #           'cache' param.
      #[:sandbox] Boolean specifying whether to perform all operations
      #           in the Amazon Mechanical Turk sandbox. Default is
      #           false.
      # ==== Returns
      # Result of call to RTurk.setup with security credentials and sandbox param.
      def setup(args={})
        args[:config] ||= Config.file
        args[:key] ||= args[:config].amazon.key
        args[:secret] ||= args[:config].amazon.secret
        args[:sandbox] = false if args[:sandbox].nil?
        if args[:config].cache
          @@cache = nil
          @@cache_file = args[:config].cache
        end
        RTurk.setup(args[:key], args[:secret], :sandbox => args[:sandbox])
      end

      #Convenience wrapper that calls RTurk::Hit.new with
      #:include_assignment_summary set to true. Takes a HIT id and
      #returns an RTurk::Hit instance.
      def rturk_hit_full(id)
        RTurk::Hit.new(id, nil, :include_assignment_summary => true)
      end

      #Returns a PStore instance tied to the cache file specified in
      #Amazon.setup (or the default).
      def cache
        @@cache ||= PStore.new(File.expand_path(@@cache_file))
      end

    end #class << self
  end #Amazon
end #Typingpool
