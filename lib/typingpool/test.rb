module Typingpool
  require 'test/unit' 

  class Test < ::Test::Unit::TestCase 
    require 'nokogiri'
    require 'fileutils'

    def MiniTest.filter_backtrace(bt)
      bt
    end

    def self.app_dir
      File.dirname(File.dirname(File.dirname(__FILE__)))
    end

    def template_dir
      File.join(Utility.lib_dir, 'templates', 'test')
    end

    def fixtures_dir
      File.join(Utility.lib_dir, 'test', 'fixtures')
    end

    def audio_dir
      File.join(template_dir, 'audio')
    end

    def config
      Config.file
    end

    def amazon_credentials?(config=self.config)
      config.amazon && config.amazon.key && config.amazon.secret
    end

    def skip_with_message(reason, skipping_what='')
      skipping_what = " #{skipping_what}" if not(skipping_what.empty?)
      skip ("Skipping#{skipping_what}: #{reason}")
      true
    end

    def skip_if_no_amazon_credentials(skipping_what='', config=self.config)
      if not (amazon_credentials?(config))
        skip_with_message('Missing or incomplete Amazon credentials', skipping_what)
      end
    end

    def s3_credentials?(config)
      amazon_credentials?(config) && config.amazon.bucket
    end

    def skip_if_no_s3_credentials(skipping_what='', config=self.config)
      if not (skip_if_no_amazon_credentials(skipping_what, config))
        if not(s3_credentials?(config))
          skip_with_message('No Amazon S3 credentials', skipping_what)
        end #if not(s3_credentials?...)
      end #if not(skip_if_no_amazon_credentials...)
    end

    def sftp_credentials?(config)
      config.sftp && config.sftp.user && config.sftp.host && config.sftp.url
    end

    def skip_if_no_sftp_credentials(skipping_what='', config=self.config)
      if not(sftp_credentials?(config))
        skip_with_message('No SFTP credentials', skipping_what)
      end #if not(sftp_credentials?...
    end

    def skip_if_no_upload_credentials(skipping_what='', config=self.config)
      if not(s3_credentials?(config) || sftp_credentials?(config))
        skip_with_message("No S3 or SFTP credentials in config", skipping_what)
      end #if not(s3_credentials?...
    end

    def add_goodbye_message(msg)
      at_exit do
        STDERR.puts msg
      end
    end

    def dummy_config(number=1)
      Typingpool::Config.file(File.join(fixtures_dir, "config-#{number}"))
    end


    def project_default
      Hash[
           :config_filename => '.config',
           :subtitle => "Typingpool's test interview transcription",
           :title => "Typingpool's Test & Interview",
           :chunks => '0:20',
           :unusual => ['Hack Day', 'Sunnyvale', 'Chad D'],
           :voice => ['Ryan', 'Havi, hacker'],
          ]
    end


    def in_temp_dir
      Typingpool::Utility.in_temp_dir{|dir| yield(dir) }
    end

    def working_url?(*args)
      Typingpool::Utility.working_url?(*args)
    end

    def fetch_url(*args)
      Typingpool::Utility.fetch_url(*args)
    end

    class Script < Test 
      require 'typingpool'
      require 'yaml'
      require 'open3'


      def audio_files(subdir='mp3')
        dir = File.join(audio_dir, subdir)
        Dir.entries(dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(dir, entry)}.select{|path| File.file?(path) }
      end

      def config_path(dir)
        ::File.join(dir, project_default[:config_filename])   
      end

      def config_from_dir(dir)
        Config.file(config_path(dir))
      end


      def setup_amazon(dir)
        Amazon.setup(:sandbox => true, :config => config_from_dir(dir))
      end


      def in_temp_tp_dir
        ::Dir.mktmpdir('typingpool_') do |dir|
          setup_temp_tp_dir(dir)
          yield(dir)
        end
      end

      def setup_temp_tp_dir(dir)
        make_temp_tp_dir_config(dir)
        FileUtils.cp_r(::File.join(template_dir, 'projects'), dir)
      end

      def make_temp_tp_dir_config(dir, config=self.config)
        config.transcripts = ::File.join(dir, 'projects')
        config.cache = ::File.join(dir, '.cache')
        config['assign']['reward'] = '0.02'
        config.assign.to_hash.delete('qualify')
        write_config(config, dir, project_default[:config_filename])   
      end

      def write_config(config, dir, filename=project_default[:config_filename])
        path = ::File.join(dir, filename)
        ::File.open(path, 'w') do |out|
          out << YAML.dump(config.to_hash)
        end
        path
      end

      def temp_tp_dir_project_dir(temp_tp_dir)
        ::File.join(temp_tp_dir, 'projects', project_default[:title])
      end

      def temp_tp_dir_project(dir, config=config_from_dir(dir))
        Project.new(project_default[:title], config)
      end

      def call_script(*args)
        Utility.system_quietly(*args)
      end

      def path_to_tp_make
        ::File.join(self.class.app_dir, 'bin', 'tp-make')
      end

      def call_tp_make(*args)
        call_script(path_to_tp_make, *args)
      end

      def tp_make(in_dir, config=config_path(in_dir), audio_subdir='mp3')
        call_tp_make(
                     '--config', config, 
                     '--chunks', project_default[:chunks],
                     *[:title, :subtitle].map{|param| ["--#{param}", project_default[param]] }.flatten,
                     *[:voice, :unusual].map{|param| project_default[param].map{|value| ["--#{param}", value] } }.flatten,
                     *audio_files(audio_subdir).map{|path| ['--file', path]}.flatten
                     )
      end

      def path_to_tp_finish
        ::File.join(self.class.app_dir, 'bin', 'tp-finish')
      end

      def call_tp_finish(*args)
        call_script(path_to_tp_finish, '--sandbox', *args)
      end

      def tp_finish(dir, config_path=self.config_path(dir))
        call_tp_finish(
                       project_default[:title],
                       '--config', config_path
                       )
      end


      def path_to_tp_assign
        File.join(self.class.app_dir, 'bin', 'tp-assign')
      end

      def call_tp_assign(*args)
        call_script(path_to_tp_assign, '--sandbox', *args)
      end

      def assign_default
        Hash[
             :template => 'interview/phone',
             :deadline => '5h',
             :lifetime => '10h',
             :approval => '10h',
             :qualify => ['approval_rate >= 90', 'hits_approved > 10'],
             :keyword => ['test', 'mp3', 'typingpooltest']
            ]
      end

      def tp_assign(dir, config_path=config_path(dir))
        call_tp_assign(
                       project_default[:title],
                       assign_default[:template],
                       '--config', config_path,
                       *[:deadline, :lifetime, :approval].map{|param| ["--#{param}", assign_default[param]] }.flatten,
                       *[:qualify, :keyword].map{|param| assign_default[param].map{|value| ["--#{param}", value] } }.flatten
                       )
      end

      def path_to_tp_collect
        File.join(self.class.app_dir, 'bin', 'tp-collect')
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


      def path_to_tp_review
        File.join(self.class.app_dir, 'bin', 'tp-review')
      end

      def tp_review_with_fixture(dir, fixture_path, choices)
        output = {}
        Open3.popen3(path_to_tp_review, '--sandbox', '--fixture', fixture_path, '--config', config_path(dir), project_default[:title]) do |stdin, stdout, stderr, wait_thr|
          choices.each do |choice|
            stdin.puts(choice)
            if choice.strip.match(/^r/i)
              stdin.puts("No reason - this is a test")
            end
          end
          output[:out] = stdout.gets(nil)
          output[:err] = stderr.gets(nil)
          [stdin, stdout, stderr].each{|stream| stream.close }
          output[:status] = wait_thr.value
        end
        output
      end

      def path_to_tp_config
        File.join(self.class.app_dir, 'bin', 'tp-config')
      end

      def tp_config(*args)
        call_script(path_to_tp_config, *args)
      end

      def tp_config_with_input(args, input)
        output = {}
        Open3.popen3(path_to_tp_config, *args) do |stdin, stdout, stderr, wait_thr|
          input.each do |sending|
            stdin.puts(sending)
          end
          output[:out] = stdout.gets(nil)
          output[:err] = stderr.gets(nil)
          [stdin, stdout, stderr].each{|stream| stream.close }
          output[:status] = wait_thr.value
        end #Open3.popen3...
        output
      end

      def fixture_project_dir(name)
        File.join(fixtures_dir, name)
      end

      def make_fixture_project_dir(name)
        dir = fixture_project_dir(name)
        if File.exists? dir
          raise Error::Test, "Fixture project already exists for #{name} at #{dir}"
        end
        ::Dir.mkdir(dir)
        dir
      end

      def remove_fixture_project_dir(name)
        FileUtils.remove_entry_secure(fixture_project_dir(name), :secure => true)
      end

      def with_fixtures_in_temp_tp_dir(dir, fixture_prefix)
        [['data', 'id.txt'],['data','assignment.csv']].each do |path_elems|
          project_path = File.join(temp_tp_dir_project_dir(dir), *path_elems)
          fixture_path = File.join(fixtures_dir, [fixture_prefix, path_elems.last].join )
          yield(fixture_path, project_path)
        end
      end

      def copy_fixtures_to_temp_tp_dir(dir, fixture_prefix)
        with_fixtures_in_temp_tp_dir(dir, fixture_prefix) do |fixture_path, project_path|
          FileUtils.mv(project_path, File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}"))
          FileUtils.cp(fixture_path, project_path)
        end
      end

      def rm_fixtures_from_temp_tp_dir(dir, fixture_prefix)
        with_fixtures_in_temp_tp_dir(dir, fixture_prefix) do |fixture_path, project_path|
          path_to_orig = File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}")
          File.exists?(path_to_orig) or raise Error::Test, "Couldn't find original file '#{path_to_orig}' when trying to restore it to original location"
          FileUtils.rm(project_path)
          FileUtils.mv(path_to_orig, project_path)
        end
      end

      def assert_has_transcript(dir, transcript_file='transcript.html')
        transcript_path = File.join(temp_tp_dir_project_dir(dir), transcript_file)
        assert(File.exists?(transcript_path))
        assert(not((transcript = IO.read(transcript_path)).empty?))
        transcript
      end

      def assert_has_partial_transcript(dir)
        assert_has_transcript(dir, 'transcript_in_progress.html')
      end

      def assert_assignment_csv_has_transcription_count(count, project)
        assert_equal(count, project.local.csv('data', 'assignment.csv').reject{|assignment| assignment['transcription'].to_s.empty?}.size)
      end

      def assert_html_has_audio_count(count, html)
        assert_equal(count, noko(html).css('audio').size)
      end

  def noko(html)
    Nokogiri::HTML(html) 
  end


  def vcr_dir
    File.join(fixtures_dir, 'vcr')
  end


    end #Script
  end #Test
end #Typingpool
