module Typingpool
  module Utility
    module Test
      module Script
        require 'yaml'
        require 'fileutils'
        require 'open3'
        require 'tmpdir'
        require 'typingpool/utility/test'
        
        include Typingpool::Utility::Test

        
        @@readymade_project_path = nil

        def with_temp_readymade_project
          Dir.mktmpdir('typingpool_') do |transcripts_dir|
            FileUtils.cp_r(File.join(readymade_project_path, '.'), transcripts_dir)
            config = reconfigure_for_transcripts_dir(
                                                     Config.file(config_path(transcripts_dir)),
                                                     transcripts_dir)
            write_config(transcripts_dir, config)
            reconfigure_project(Project.new(project_default[:title], config))
            yield(transcripts_dir)
          end
        end

        def with_temp_transcripts_dir
          Dir.mktmpdir('typingpool_') do |transcripts_dir|
            write_testing_config_for_transcripts_dir(transcripts_dir, self.config)
            yield(transcripts_dir)
          end
        end
        
        def reconfigure_for_s3(config)
          unless s3_credentials?(config)
            raise Error::Test, "No S3 credentials available"
          end
          config.to_hash.delete('sftp')
          config
        end

        def reconfigure_for_transcripts_dir(config, transcripts_dir)
          config.transcripts = transcripts_dir
          config.cache = File.join(transcripts_dir, '.cache')
          config
        end
        
        def reconfigure_for_testing(config)
          config['assign']['reward'] = '0.02'
          config.assign.to_hash.delete('qualify')
          config
        end
        
        def write_config(dir, config, filename=project_default[:config_filename])
          path = File.join(dir, filename)
          File.write(path, YAML.dump(config.to_hash))
          path
        end

        def write_testing_config_for_transcripts_dir(transcripts_dir, config=self.config)
          write_config(
                       transcripts_dir,
                       reconfigure_for_transcripts_dir(reconfigure_for_testing(config), transcripts_dir),
                       project_default[:config_filename])
        end

        
        def readymade_project_path
          unless @@readymade_project_path
            transcripts_dir = @@readymade_project_path = Dir.mktmpdir('typingpool_')
            do_later{ FileUtils.remove_entry_secure(transcripts_dir) }
            write_testing_config_for_transcripts_dir(transcripts_dir, reconfigure_for_s3(self.config))
            tp_make(transcripts_dir, config_path(transcripts_dir), 'mp3', true)
          end
          @@readymade_project_path
        end

        def config_path(dir)
          File.join(dir, project_default[:config_filename])   
        end

        #Intended to be overriden by some classes that mixin this
        #module
        def do_later
          at_exit{ yield }
        end

        def reconfigure_project(project)
          #rewrite URLs in assignment.csv according to config at config_path
          File.delete(project.local.file('data', 'id.txt'))
          project.local.create_id
          reconfigure_project_csv(project)
          project
        end

        def reconfigure_project_csv(project)
          assignments = project.local.file('data', 'assignment.csv').as(:csv)
          urls = project.create_remote_names(assignments.map{|assignment| Project.local_basename_from_url(assignment['audio_url']) }).map{|file| project.remote.file_to_url(file) }
          assignments.each! do |assignment|
            assignment['audio_url'] = urls.shift
            assignment['project_id'] = project.local.id
          end
          assignments
        end        

        def path_to_script(script_name)
          File.join(Utility.app_dir, 'bin', script_name)
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
          call_script('tp-make', *commands)
        end

        def tp_make_with_vcr(dir, fixture_name, config_path=config_path(dir))
          tp_make(dir, config_path, 'mp3', false, *vcr_args(fixture_name))
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

        def tp_finish(dir, config_path=config_path(dir), project_title=project_default[:title], *args)
          tp_finish_inside_sandbox(dir, config_path, project_title, *args)
          tp_finish_outside_sandbox(dir, config_path, project_title, *args)
        end


        def tp_finish_inside_sandbox(dir, config_path=config_path(dir), project_title=project_default[:title], *args)
          tp_finish_outside_sandbox(dir, config_path, project_title, '--sandbox', *args)
        end

        def tp_finish_outside_sandbox(dir, config_path=config_path(dir), project_title=project_default[:title], *args)
          call_script('tp-finish', project_title, '--config', config_path, *args)
        end

        def audio_files(subdir='mp3')
          dir = File.join(audio_dir, subdir)
          Dir.entries(dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(dir, entry)}.select{|path| File.file?(path) }
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

        def tp_assign(dir, config_path=config_path(dir), project_title=project_default[:title], *args)
          call_script(
                      'tp-assign',
                      '--sandbox',
                      project_title,
                      assign_default[:template],
                      '--config', config_path,
                      *[:deadline, :lifetime, :approval].map{|param| ["--#{param}", assign_default[param]] }.flatten,
                      *[:qualify, :keyword].map{|param| assign_default[param].map{|value| ["--#{param}", value] } }.flatten,
                      *args)
          
        end

        def tp_assign_with_vcr(dir, fixture_name, config_path=config_path(dir), project_title=project_default[:title])
          project = Project.new(project_default[:title], Typingpool::Config.file(config_path))
          args = [dir, config_path, project_title, *vcr_args(fixture_name)]
          unless (Typingpool::Test.live || Typingpool::Test.record)
            args.push('--testtime', project_time(project).to_i.to_s)
          end
          tp_assign(*args)
        end

        def copy_tp_assign_fixtures(dir, fixture_prefix, config_path=config_path(dir), project_title=project_default[:title])
          project = Project.new(project_title, Config.file(config_path))
          if Typingpool::Test.record
            project_time(project, Time.now)
            with_fixtures_in_transcripts_dir(dir, "#{fixture_prefix}_", project_title) do |fixture_path, project_path|
              FileUtils.cp(project_path, fixture_path)
            end
          elsif not(Typingpool::Test.live)
            copy_fixtures_to_project_dir("#{fixture_prefix}_", File.join(dir, project_title))
            reconfigure_project_csv(project)
          end
        end

        def tp_collect_with_fixture(dir, fixture_name, are_recording=false)
          fixture_handle = File.join(vcr_dir, fixture_name)
          args = ['tp-collect', '--sandbox', '--testfixture', fixture_handle, '--config', config_path(dir)]
          if are_recording
            delete_vcr_fixture(fixture_name)
            args.push('--testfixturerecord')
          end
          call_script(*args)
        end

        def tp_review_with_fixture(transcripts_dir, fixture_name, choices, are_recording=false, project_name=nil)
          fixture_handle = File.join(vcr_dir, fixture_name)
          output = {}
          args = [
                  File.join(Utility.app_dir, 'bin', 'tp-review'),
                  '--sandbox',
                  '--config', config_path(transcripts_dir),
                  '--testfixture', fixture_handle
                 ]
          args.push(project_name) if project_name
          if are_recording
            delete_vcr_fixture(fixture_name)
            args.push('--testfixturerecord')
          end
          
          Open3.popen3(*args) do |stdin, stdout, stderr, wait_thr|
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
        
        def project_time(project, time=nil)
          file = project.local.file('data', 'time.txt')
          if time
            file.write(time.to_i)
          else
            time = Time.at(file.read.to_i)
          end
          time
        end
        
        def simulate_failed_audio_upload_in(dir, config_path=config_path(dir))
          project = Typingpool::Project.new(project_default[:title], Config.file(config_path))
          csv = project.local.file('data', 'assignment.csv').as(:csv)
          csv.each!{|a| a['audio_uploaded'] = 'maybe'}
        end

        def make_fixture_transcripts_dir(name)
          dir = File.join(fixtures_dir, name)
          if File.exist? dir
            raise Error::Test, "Fixture transcript dir already exists for #{name} at #{dir}"
          end
          Dir.mkdir(dir)
          dir
        end

        def with_fixtures_in_project_dir(fixture_prefix, project_path)
          fixtures = Dir.entries(fixtures_dir).select{|entry| entry.include?(fixture_prefix) && entry.index(fixture_prefix) == 0 }.select{|entry| File.file?(File.join(fixtures_dir, entry)) }
          fixtures.map!{|fixture| fixture[fixture_prefix.size .. -1] }
          fixtures.each do |fixture|
            project_fixture_path = File.join(project_path, 'data', fixture)
            source_fixture_path = File.join(fixtures_dir, [fixture_prefix, fixture].join )
            yield(source_fixture_path, project_fixture_path)
          end
        end

        def copy_fixtures_to_project_dir(fixture_prefix, project_path)
          copies = 0
          with_fixtures_in_project_dir(fixture_prefix, project_path) do |source_fixture_path, project_fixture_path|
            if File.exist? project_fixture_path
              FileUtils.mv(project_fixture_path, File.join(File.dirname(project_fixture_path), "orig_#{File.basename(project_fixture_path)}"))
            end
            FileUtils.cp(source_fixture_path, project_fixture_path)
            copies += 1
          end
          copies > 0 or raise Error, "No fixtures to copy with prefix #{fixture_prefix}"
          copies
        end

        def restore_project_dir_from_fixtures(fixture_prefix, project_path)
          with_fixtures_in_project_dir(fixture_prefix, project_path) do |source_fixture_path, project_fixture_path|
            FileUtils.rm(project_fixture_path)
            path_to_orig = File.join(File.dirname(project_fixture_path), "orig_#{File.basename(project_fixture_path)}")
            if File.exist?(path_to_orig)
              FileUtils.mv(path_to_orig, project_fixture_path)
            end
          end #with_fixtures_in_transctips_dir
        end

        def project_transcript_count(project, which_csv)
          project.local.file('data', which_csv).as(:csv).reject{|assignment| assignment['transcript'].to_s.empty?}.size
        end

        def split_reviews(output)
          output.split(/Transcript for\b/)
        end

        
      end #Script      
    end #Test
  end #Utility
end #Typingpool
