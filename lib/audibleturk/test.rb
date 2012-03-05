module Audibleturk
  require 'test/unit'
  class Test < ::Test::Unit::TestCase
    class Error; end

    def MiniTest.filter_backtrace(bt)
      bt
    end

    def self.app_dir
      File.dirname(File.dirname(File.dirname(__FILE__)))
    end

    def template_dir
      File.join(self.class.app_dir, 'templates', 'test')
    end

    def fixtures_dir
      File.join(self.class.app_dir, 'test', 'fixtures')
    end


    class Script < Test 
      #Yes, big fat integration tests written in Test::Unit. Get over it.
      require 'audibleturk'
      require 'tmpdir'
      require 'yaml'
      require 'set'
      require 'net/http'

      def audio_dir
        File.join(template_dir, 'audio')
      end

      def audio_files(subdir='mp3')
        dir = File.join(audio_dir, subdir)
        Dir.entries(dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(dir, entry)}.select{|path| File.file?(path) }
      end

      def config
        Audibleturk::Config.file
      end

      def config_path(dir)
        File.join(dir, project_default[:config_filename])   
      end

      def config_from_dir(dir)
        Audibleturk::Config.file(config_path(dir))
      end

      def amazon_credentials?(config=self.config)
        config.param['aws'] && config.param['aws']['key'] && config.param['aws']['secret']
      end

      def skip_if_no_amazon_credentials(skipping='', config=self.config)
        skipping = " #{skipping}" if not(skipping.empty?)
        if not (amazon_credentials?(config))
          skip ("Skipping#{skipping}: No Amazon credentials") 
        end
      end

      def amazon_result_params
        {:id_at => 'typingpool_project_id', :url_at => 'typingpool_url'}
      end

      def setup_amazon(dir)
        Audibleturk::Amazon.setup(:sandbox => true, :config => config_from_dir(dir))
      end

      def in_temp_tp_dir
        Dir.mktmpdir('typingpool_') do |dir|
          setup_temp_tp_dir(dir)
          yield(dir)
        end
      end

      def setup_temp_tp_dir(dir)
        make_temp_tp_dir_config(dir)
        FileUtils.cp_r(File.join(template_dir, 'projects'), dir)
      end

      def make_temp_tp_dir_config(dir, config=self.config)
        config.param['local'] = File.join(dir, 'projects')
        config.param['cache'] = File.join(dir, '.cache')
        config.param['app'] = self.class.app_dir
        config.param['assignments']['reward'] = '0.02'
        File.open(config_path(dir), 'w') do |out|
          out << YAML.dump(config.param)
        end
      end

      def temp_tp_dir_project_dir(temp_tp_dir)
        File.join(temp_tp_dir, 'projects', project_default[:title])
      end

      def temp_tp_dir_project(dir)
        Audibleturk::Project.new(project_default[:title], config_from_dir(dir))
      end

      def working_url?(url, max_redirects=6)
        response = nil
        seen = Set.new
        loop do
          url = URI.parse(url)
          break if seen.include? url.to_s
          break if seen.size > max_redirects
          seen.add(url.to_s)
          response = Net::HTTP.new(url.host, url.port).request_head(url.path)
          if response.kind_of?(Net::HTTPRedirection)
            url = response['location']
          else
            break
          end
        end
        response.kind_of?(Net::HTTPSuccess) && url.to_s
      end

      def call_script(*args)
        Audibleturk::Utility.system_quietly(*args)
      end

      def path_to_tp_make
        File.join(self.class.app_dir, 'bin', 'make.rb')
      end

      def call_tp_make(*args)
        call_script(path_to_tp_make, *args)
      end

      def project_default
        Hash[
             :config_filename => '.config',
             :subtitle => 'Typingpool test interview transcription',
             :title => 'TestTpInterview',
             :chunks => '0:20',
             :unusual => ['Hack Day', 'Sunnyvale', 'Chad D'],
             :voice => ['Ryan', 'Havi, hacker'],
            ]
      end

      def tp_make(in_dir, audio_subdir='mp3')
        call_tp_make(
                     '--config', config_path(in_dir), 
                     '--chunks', project_default[:chunks],
                     *[:title, :subtitle].map{|param| ["--#{param}", project_default[param]] }.flatten,
                     *[:voice, :unusual].map{|param| project_default[param].map{|value| ["--#{param}", value] } }.flatten,
                     *audio_files(audio_subdir).map{|path| ['--file', path]}.flatten
                     )
      end

      def path_to_tp_finish
        File.join(self.class.app_dir, 'bin', 'finish.rb')
      end

      def call_tp_finish(*args)
        call_script(path_to_tp_finish, '--sandbox', *args)
      end

      def tp_finish(dir)
        call_tp_finish(
                       project_default[:title],
                       '--config', config_path(dir)
                       )
      end


      def path_to_tp_assign
        File.join(self.class.app_dir, 'bin', 'assign.rb')
      end

      def call_tp_assign(*args)
        call_script(path_to_tp_assign, '--sandbox', *args)
      end

      def assign_default
        Hash[
             :template => 'interview/phone/1minute',
             :deadline => '5h',
             :lifetime => '10h',
             :approval => '10h',
             :qualify => ['approval_rate >= 90', 'hits_approved > 10'],
             :keyword => ['test', 'mp3', 'typingpooltest']
            ]
      end

      def tp_assign(dir)
        call_tp_assign(
                       project_default[:title],
                       assign_default[:template],
                       '--config', config_path(dir),
                       *[:deadline, :lifetime, :approval].map{|param| ["--#{param}", assign_default[param]] }.flatten,
                       *[:qualify, :keyword].map{|param| assign_default[param].map{|value| ["--#{param}", value] } }.flatten
                       )
      end

      def path_to_tp_collect
        File.join(self.class.app_dir, 'bin', 'collect.rb')
      end

      def call_tp_collect(fixture_path, *args)
        call_script(path_to_tp_collect, '--sandbox', '--fixture', fixture_path, *args)
      end

      def tp_collect_with_fixture(dir, fixture_path)
        call_tp_collect(
                        fixture_path,
                        '--config', config_path(dir)
                        )
      end

      def tp_collect_fixture_project_dir
        File.join(fixtures_dir, 'tp_collect_project')
      end

      def make_tp_collect_fixture_project_dir
        if File.exists? tp_collect_fixture_project_dir
          raise Test::Error, "Fixture project already exists for tp-collect at #{tp_collect_fixture_project_dir}"
        end
        Dir.mkdir(tp_collect_fixture_project_dir)
        tp_collect_fixture_project_dir
      end

      def tp_collect_fixture_gen_project_dir
        if @dir.nil?
          @dir = IO.read(File.join(fixtures_dir, '.tp_collect_meta'))
          @dir or raise "Can't find the project dir created by make_tp_collect_fixture_1.rb."
          File.exists?(@dir) or raise Test::Error, "The tp_collect fixture dir is missing (#{@dir})"
          File.directory?(@dir) or raise Test::Error, "Not a dir (#{@dir})"
        end
        @dir
      end
    end #Script
  end #Test
end #Audibleturk
