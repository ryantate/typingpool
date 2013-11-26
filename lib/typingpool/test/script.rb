module Typingpool
  class Test 
    class Script < Test 
      require 'typingpool'
      require 'yaml'
      require 'open3'
      require 'fileutils'
      require 'nokogiri'

      @@readymade_project_path = nil

      def with_temp_readymade_project
        with_temp_transcripts_dir do |dir|
          setup_readymade_project_into(config_path(dir))
          yield(dir)
        end
      end

      def setup_readymade_project_into(config_path)
        init_readymade_project
        copy_readymade_project_into(config_path)
        reconfigure_readymade_project_in(config_path)
      end

      def init_readymade_project
        unless @@readymade_project_path
          dir = @@readymade_project_path = Dir.mktmpdir('typingpool_')
          Minitest.after_run{ FileUtils.remove_entry_secure(dir) }
          make_transcripts_dir_config(dir, Config.file(setup_s3_config(dir, self.config)))
          tp_make(dir, config_path(dir), 'mp3', true)
        end 
      end

      def copy_readymade_project_into(config_path)
        config = Typingpool::Config.file(config_path)
        FileUtils.cp_r(File.join(@@readymade_project_path, '.'), File.dirname(config_path))
      end

      def reconfigure_readymade_project_in(config_path)
        #rewrite URLs in assignment.csv according to config at config_path
        make_transcripts_dir_config(File.dirname(config_path), Config.file(config_path))
        project = Project.new(project_default[:title], Config.file(config_path))
        File.delete(project.local.file('data', 'id.txt'))
        project.local.create_id
        id = project.local.id
        reconfigure_project_csv_in(config_path)
      end

      def reconfigure_project_csv_in(config_path)
        project = Project.new(project_default[:title], Config.file(config_path))
        assignments = project.local.file('data', 'assignment.csv').as(:csv)
        urls = project.create_remote_names(assignments.map{|assignment| Project.local_basename_from_url(assignment['audio_url']) }).map{|file| project.remote.file_to_url(file) }
        assignments.each! do |assignment|
          assignment['audio_url'] = urls.shift
          assignment['project_id'] = project.local.id
        end
      end

      def simulate_failed_audio_upload_in(dir, config_path=config_path(dir))
        project = Project.new(project_default[:title], Config.file(config_path))
        csv = project.local.file('data', 'assignment.csv').as(:csv)
        csv.each!{|a| a['audio_uploaded'] = 'maybe'}
      end

      def audio_files(subdir='mp3')
        dir = File.join(audio_dir, subdir)
        Dir.entries(dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(dir, entry)}.select{|path| File.file?(path) }
      end

      def config_path(dir)
        File.join(dir, project_default[:config_filename])   
      end

      def with_temp_transcripts_dir
        Dir.mktmpdir('typingpool_') do |dir|
          make_transcripts_dir_config(dir, self.config)
          yield(dir)
        end
      end

      def setup_s3_config(dir, config=Config.file(config_path(dir)), filename='.config_s3')
        return unless s3_credentials?(config)
        config.to_hash.delete('sftp')
        write_config(config, dir, filename)
      end

      def setup_s3_config_with_bad_password(dir, config=Config.file(config_path(dir)))
        bad_password = 'f'
        refute_equal(config.to_hash['amazon']['secret'], bad_password)
        config.to_hash['amazon']['secret'] = bad_password
        setup_s3_config(dir, config, '.config_s3_bad')
      end

      def make_transcripts_dir_config(dir, config=self.config)
        config.transcripts = dir
        config.cache = File.join(dir, '.cache')
        config['assign']['reward'] = '0.02'
        config.assign.to_hash.delete('qualify')
        write_config(config, dir, project_default[:config_filename])   
      end

      def write_config(config, dir, filename=project_default[:config_filename])
        path = File.join(dir, filename)
        File.write(path, YAML.dump(config.to_hash))
        path
      end

      def transcripts_dir_project(dir, config=Config.file(config_path(dir)))
        Project.new(project_default[:title], config)
      end

      def call_script(script_name, *args)
        out, err, status = Open3.capture3(path_to_script(script_name), *args)
        if status.success?
          return [out.to_s.chomp, err.to_s.chomp]
        else
          if err
            raise Error::Shell, err.chomp
          else
            raise Error::Shell
          end
        end
        #Utility.system_quietly(path_to_script(script_name), *args)
      end

      def path_to_script(script_name)
        File.join(self.class.app_dir, 'bin', script_name)
      end

      def vcr_args(fixture_name)
        args = []
        if fixture = cleared_vcr_fixture_path_for(fixture_name)
          args.push('--testfixture', fixture)
          if Typingpool::Test.record
            args.push('--testfixturerecord') 
          end
        end #if fixture = ...
        args
      end

      def call_tp_make(*args)
        call_script('tp-make', *args)
      end

      def tp_make(in_dir, config=config_path(in_dir), audio_subdir='mp3', devtest_mode_skipping_upload=false, *args)
        commands = [
                     '--config', config, 
                     '--chunks', project_default[:chunks],
                     *[:title, :subtitle].map{|param| ["--#{param}", project_default[param]] }.flatten,
                     *[:voice, :unusual].map{|param| project_default[param].map{|value| ["--#{param}", value] } }.flatten,
                     *audio_files(audio_subdir).map{|path| ['--file', path]}.flatten, 
                    *args
                   ]
        commands.push('--testnoupload', '--testkeepmergefile') if devtest_mode_skipping_upload
        call_tp_make(*commands)
      end

      def tp_make_with_vcr(dir, fixture_name, config_path=config_path(dir))
        tp_make(dir, config_path, 'mp3', false, *vcr_args(fixture_name))
      end

      def call_tp_finish(*args)
        call_script('tp-finish', *args)
      end

      def tp_finish(dir, config_path=config_path(dir), *args)
        tp_finish_inside_sandbox(dir, config_path, *args)
        tp_finish_outside_sandbox(dir, config_path, *args)
      end


      def tp_finish_inside_sandbox(dir, config_path=config_path(dir), *args)
        tp_finish_outside_sandbox(dir, config_path, '--sandbox', *args)
      end

      def tp_finish_outside_sandbox(dir, config_path=config_path(dir), *args)
        call_tp_finish(project_default[:title], '--config', config_path, *args)
      end

      def call_tp_assign(*args)
        call_script('tp-assign', '--sandbox', *args)
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

      def tp_assign(dir, config_path=config_path(dir), *args)
        call_tp_assign(
                       project_default[:title],
                       assign_default[:template],
                       '--config', config_path,
                       *[:deadline, :lifetime, :approval].map{|param| ["--#{param}", assign_default[param]] }.flatten,
                       *[:qualify, :keyword].map{|param| assign_default[param].map{|value| ["--#{param}", value] } }.flatten,
                       *args)
               
      end

      def tp_assign_with_vcr(dir, fixture_name, config_path=config_path(dir))
        project = transcripts_dir_project(dir, Typingpool::Config.file(config_path))
        args = [dir, config_path, *vcr_args(fixture_name)]
        unless (Typingpool::Test.live || Typingpool::Test.record)
          args.push('--testtime', project_time(project).to_i.to_s)
        end
        tp_assign(*args)
      end

      def copy_tp_assign_fixtures(dir, fixture_prefix, config_path=config_path(dir))
        project = transcripts_dir_project(dir, Typingpool::Config.file(config_path))
        if Typingpool::Test.record
          project_time(project, Time.now)
          with_fixtures_in_transcripts_dir(dir, "#{fixture_prefix}_") do |fixture_path, project_path|
            FileUtils.cp(project_path, fixture_path)
          end
        elsif not(Typingpool::Test.live)
          copy_fixtures_to_transcripts_dir(dir, "#{fixture_prefix}_")
          reconfigure_project_csv_in(config_path)
        end
      end

      def project_time(project, time=nil)
        file = project.local.file('data', 'time.txt')
        if time
          file.write(time.to_i)
        else
          time = Time.at(file.read.to_i)
        end
        time
      end

      def call_tp_collect(fixture_path, *args)
        call_script('tp-collect', '--sandbox', '--fixture', fixture_path, *args)
      end

      def tp_collect_with_fixture(dir, fixture_path)
        call_tp_collect(
                        fixture_path,
                        '--config', config_path(dir)
                        )
      end


      def tp_review_with_fixture(dir, fixture_path, choices)
        output = {}
        Open3.popen3(File.join(self.class.app_dir, 'bin', 'tp-review'), '--sandbox', '--fixture', fixture_path, '--config', config_path(dir), project_default[:title]) do |stdin, stdout, stderr, wait_thr|
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

      def tp_config(*args)
        call_script('tp-config', *args)
      end

      def tp_config_with_input(args, input)
        output = {}
        Open3.popen3(path_to_script('tp-config'), *args) do |stdin, stdout, stderr, wait_thr|
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
        Dir.mkdir(dir)
        dir
      end

      def remove_fixture_project_dir(name)
        FileUtils.remove_entry_secure(fixture_project_dir(name), :secure => true)
      end

      def with_fixtures_in_transcripts_dir(dir, fixture_prefix)
        fixtures = Dir.entries(fixtures_dir).select{|entry| entry.include?(fixture_prefix) && entry.index(fixture_prefix) == 0 }.select{|entry| File.file?(File.join(fixtures_dir, entry)) }
        fixtures.map!{|fixture| fixture[fixture_prefix.size .. -1] }
        fixtures.each do |fixture|
          project_path = File.join(transcripts_dir_project(dir).local, 'data', fixture)
          fixture_path = File.join(fixtures_dir, [fixture_prefix, fixture].join )
          yield(fixture_path, project_path)
        end
      end

      def copy_fixtures_to_transcripts_dir(dir, fixture_prefix)
        copies = 0
        with_fixtures_in_transcripts_dir(dir, fixture_prefix) do |fixture_path, project_path|
          if File.exists? project_path
            FileUtils.mv(project_path, File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}"))
          end
          FileUtils.cp(fixture_path, project_path)
          copies += 1
        end
        copies > 0 or raise Error, "No fixtures to copy with prefix #{fixture_prefix} from dir #{dir}"
        copies
      end

      def rm_fixtures_from_transcripts_dir(dir, fixture_prefix)
        with_fixtures_in_transcripts_dir(dir, fixture_prefix) do |fixture_path, project_path|
          FileUtils.rm(project_path)
          path_to_orig = File.join(File.dirname(project_path), "orig_#{File.basename(project_path)}")
          if File.exists?(path_to_orig)
            FileUtils.mv(path_to_orig, project_path)
          end
        end
      end

      def assert_has_transcript(dir, transcript_file='transcript.html')
        transcript_path = File.join(transcripts_dir_project(dir).local, transcript_file)
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
        assert_equal(count, Nokogiri::HTML(html).css('audio').size)
      end

      def assert_all_assets_have_upload_status(assignment_csv, type, status)
        recorded_uploads = assignment_csv.map{|assignment| assignment["#{type}_uploaded"] }
        refute_empty(recorded_uploads)
        assert_equal(recorded_uploads.count, recorded_uploads.select{|uploaded| uploaded == status }.count)
      end

      def assert_script_abort_match(args, regex)
        with_temp_transcripts_dir do |dir|
          exception = assert_raises(Typingpool::Error::Shell) do
            yield([*args, '--config', config_path(dir)])
          end
          assert_match(regex, exception.message)
        end #with_temp_transcripts_dir do...
      end
    end #Script
  end #Test
end #Typingpool
