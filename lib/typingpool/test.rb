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

    def fixtures_dir
      File.join(Utility.lib_dir, 'test', 'fixtures')
    end

    def audio_dir
      File.join(fixtures_dir, 'audio')
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
        Dir.mkdir(File.join(dir, 'projects'))
      end

      def setup_s3_config(dir, config=config_from_dir(dir), filename='.config_s3')
        return unless s3_credentials?(config)
        config.to_hash.delete('sftp')
        write_config(config, dir, filename)
      end

      def setup_s3_config_with_bad_password(dir, config=config_from_dir(dir))
        bad_password = 'f'
        refute_equal(config.to_hash['amazon']['secret'], bad_password)
        config.to_hash['amazon']['secret'] = bad_password
        setup_s3_config(dir, config, '.config_s3_bad')
      end

      def make_temp_tp_dir_config(dir, config=self.config)
        config.transcripts = File.join(dir, 'projects')
        config.cache = File.join(dir, '.cache')
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
        call_script(path_to_tp_finish, *args)
      end

      def tp_finish(dir, config_path=self.config_path(dir))
        tp_finish_inside_sandbox(dir, config_path)
        tp_finish_outside_sandbox(dir, config_path)
      end


      def tp_finish_inside_sandbox(dir, config_path=self.config_path(dir))
        tp_finish_outside_sandbox(dir, config_path, '--sandbox')
      end

      def tp_finish_outside_sandbox(dir, config_path=self.config_path(dir), *args)
        call_tp_finish(
                       project_default[:title],
                       '--config', config_path, 
                       *args
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
        fixtures = Dir.entries(fixtures_dir).select{|entry| entry.include?(fixture_prefix) && entry.index(fixture_prefix) == 0 }.select{|entry| File.file?(File.join(fixtures_dir, entry)) }
        fixtures.map!{|fixture| fixture[fixture_prefix.size .. -1] }
        fixtures.each do |fixture|
          project_path = File.join(temp_tp_dir_project_dir(dir), 'data', fixture)
          fixture_path = File.join(fixtures_dir, [fixture_prefix, fixture].join )
          yield(fixture_path, project_path)
        end
      end

      def copy_fixtures_to_temp_tp_dir(dir, fixture_prefix)
        with_fixtures_in_temp_tp_dir(dir, fixture_prefix) do |fixture_path, project_path|
          if File.exists? project_path
            FileUtils.mv(project_path, File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}"))
          end
          FileUtils.cp(fixture_path, project_path)
        end
      end

      def rm_fixtures_from_temp_tp_dir(dir, fixture_prefix)
        with_fixtures_in_temp_tp_dir(dir, fixture_prefix) do |fixture_path, project_path|
          FileUtils.rm(project_path)
          path_to_orig = File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}")
          if File.exists?(path_to_orig)
            FileUtils.mv(path_to_orig, project_path)
          end
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

      def assert_assignment_csv_has_transcription_count(count, project, which_csv='assignment.csv')
        assert_equal(count, project.local.file('data', which_csv).as(:csv).reject{|assignment| assignment['transcript'].to_s.empty?}.size)
      end

      def assert_html_has_audio_count(count, html)
        assert_equal(count, noko(html).css('audio').size)
      end

      def assert_all_assets_have_upload_status(assignment_csv, types, status)
        types.each do |type|
          recorded_uploads = assignment_csv.map{|assignment| assignment["#{type}_uploaded"] }
          refute_empty(recorded_uploads)
          assert_equal(recorded_uploads.count, recorded_uploads.select{|uploaded| uploaded == status }.count)
        end
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
