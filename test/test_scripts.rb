#!/usr/bin/env ruby

require 'test/unit'


def MiniTest.filter_backtrace(bt)
  bt
end

class TestScripts < Test::Unit::TestCase
  def self.app_dir
    File.join(File.dirname(__FILE__), '..')
  end

  $:.unshift File.join(self.app_dir, 'lib')

  require 'audibleturk'
  require 'tmpdir'
  require 'yaml'
  require 'set'
  require 'net/http'

  def template_dir
    File.join(self.class.app_dir, 'templates', 'test')
  end

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

  def add_goodbye_message(msg)
    at_exit do
      STDERR.puts msg
    end
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

  class TestTpMake < TestScripts                   
    def test_abort_with_no_files
      assert_raise(Audibleturk::Error::Shell) do
        call_tp_make('--title', 'Foo', '--chunks', '0:20')
      end
    end

    def test_abort_with_no_title
      assert_raise(Audibleturk::Error::Shell) do
        call_tp_make('--file', audio_files[0])
      end
    end

    def test_tp_make_and_tp_finish
      if not(amazon_credentials?)
        add_no_amazon_message("Skipping tp-make and tp-finish test")
        return
      end
      Dir.entries(audio_dir).select{|entry| File.directory?(File.join(audio_dir, entry))}.reject{|entry| entry.match(/^\./) }.each do |subdir|
        in_temp_tp_dir do |dir|
          project = nil
          assert_nothing_raised do
            assert(tp_make(dir, subdir))
            assert_nothing_raised do
              project = Audibleturk::Project.new(project_default[:title], Audibleturk::Config.file(config_path(dir)))
            end
            assert_not_nil(project.local)
            assert_not_nil(project.local.id)
            assert(project.local.audio_chunks.size >= 6)
            assert(project.local.audio_chunks.size <= 7)
            assert_equal(project_default[:subtitle], project.local.subtitle)
            assignments = nil
            assert_nothing_raised do 
              assignments = project.local.read_csv('assignment')
            end
            assert_equal(project.local.audio_chunks.size, assignments.size)
            assignments.each do |assignment|
              assert_not_nil(assignment['url'])
              assert(working_url? assignment['url'])
              assert_equal(assignment['project_id'], project.local.id)
              assert_equal(assignment['unusual'].split(/\s*,\s*/), project_default[:unusual])
              project_default[:voice].each_with_index do |voice, i|
                name, description = voice.split(/\s*,\s*/)
                assert_equal(name, assignment["voice#{i+1}"])
                if not(description.to_s.empty?)
                  assert_equal(description, assignment["voice#{i+1}title"])
                end
              end
            end
          end #assert_nothing_raised
          assert_nothing_raised do
            assert(tp_finish(dir))
            assignments = nil
            assert_nothing_raised do
              assignments = project.local.read_csv('assignment')
            end
            assignments.each do |assignment|
              assert_not_nil(assignment['url'])
              assert(not(working_url? assignment['url']))
            end
          end #assert_nothing_raised
        end #in_temp_tp_dir
      end #Dir.entries
    end #def test_tp_make_and_tp_finish
  end #TestTpMake


  class TestTpAssign < TestScripts
    #TODO: test that qualifications are sent (will need heroic effort
    #(or at least some xml parsing) since rturk doesn't provide an
    #easy way to look at HIT qualifications
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

    def test_abort_with_no_input
      assert_raise(Audibleturk::Error::Shell){call_tp_assign}
    end

    def test_abort_with_no_template
      exception = assert_raise(Audibleturk::Error::Shell){call_tp_assign(project_default[:title])}
      assert_match(exception.message, /Missing\b[^\n\r\f]*\btemplate/)
    end

    def test_abort_with_bad_timespec
      exception = assert_raise(Audibleturk::Error::Shell) do
        call_tp_assign(project_default[:title], assign_default[:template], '--lifetime', '4u')
      end
      assert_match(exception.message, /can't convert/i)
    end

    def test_abort_with_bad_qualification
      exception = assert_raise(Audibleturk::Error::Shell) do
        call_tp_assign(project_default[:title], assign_default[:template], '--qualify', 'approval_rate &= 8')
      end
      assert_match(exception.message, /bad --qualify/i)
      assert_match(exception.message, /unknown comparator/i)
      exception = assert_raise(Audibleturk::Error::Shell) do
        call_tp_assign(project_default[:title], assign_default[:template], '--qualify', 'fake_rate > 8', '--sandbox')
      end
      assert_match(exception.message, /bad --qualify/i)
      assert_match(exception.message, /unknown\b[^\n\r\f]*\btype/i)
    end

    def test_tp_assign
      if not(amazon_credentials?)
        add_no_amazon_message("Skipping tp-assign test")
        return
      end
      in_temp_tp_dir do |dir|
        tp_make(dir)
assigning_started = Time.now
        assert_nothing_raised do
          call_tp_assign(
                         project_default[:title],
                         assign_default[:template],
                         '--config', config_path(dir),
                         *[:deadline, :lifetime, :approval].map{|param| ["--#{param}", assign_default[param]] }.flatten,
                         *[:qualify, :keyword].map{|param| assign_default[param].map{|value| ["--#{param}", value] } }.flatten
                         )
        end #assert_nothing_raised
        assign_time = Time.now - assigning_started
        config = Audibleturk::Config.file(config_path(dir))
        project = Audibleturk::Project.new(project_default[:title], config)
        assert_not_nil(project.local.amazon_hit_type_id)
        params = {:id_at => 'typingpool_project_id', :url_at => 'typingpool_url'}
        Audibleturk::Amazon.setup(:sandbox => true, :config => config)
        results = nil
        assert_nothing_raised{ results = Audibleturk::Amazon::Result.all_for_project(project.local.id, params) }
        assert_equal(project.local.audio_chunks.size, results.size)
        assert_equal(Audibleturk::Utility.timespec_to_seconds(assign_default[:deadline]), results[0].hit.assignments_duration.to_i)
        #These numbers will be apart due to clock differences and
        #timing vagaries of the assignment.
        assert_in_delta((assigning_started + assign_time + Audibleturk::Utility.timespec_to_seconds(assign_default[:lifetime])).to_f, results[0].hit.expires_at.to_f, 60)
        keywords = results[0].hit_at_amazon.keywords
        assign_default[:keyword].each{|keyword| assert_includes(keywords, keyword)}
        assert_nothing_raised{tp_finish(dir)}

        assert_equal(0, Audibleturk::Amazon::Result.all_for_project(project.local.id, params).size)
      end # in_temp_tp_dir
    end

  end #TestTpAssign
end #TestScripts
