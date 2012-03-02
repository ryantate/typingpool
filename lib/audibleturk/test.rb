module Audibleturk
  require 'test/unit'
  class Test < ::Test::Unit::TestCase
    def MiniTest.filter_backtrace(bt)
      bt
    end

    def self.app_dir
      File.join(File.dirname($0), '..')
    end

    def template_dir
      File.join(self.class.app_dir, 'templates', 'test')
    end

    class Script < Test 
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

      def amazon_credentials?(config=self.config)
        config.param['aws'] && config.param['aws']['key'] && config.param['aws']['secret']
      end

      def add_no_amazon_message(message)
        add_goodbye_message("#{message} (No Amazon credentials in config file)")
      end

      def add_goodbye_message(msg)
        at_exit do
          STDERR.puts msg
        end
      end

      def in_temp_tp_dir
        Dir.mktmpdir('typingpool_') do |dir|
          make_temp_tp_dir_config(dir)
          FileUtils.cp_r(File.join(template_dir, 'projects'), dir)
          yield(dir)
        end
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


    end #Script
  end #Test
end #Audibleturk
