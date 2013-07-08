#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestTpAssign < Typingpool::Test::Script
  #TODO: test that qualifications are sent (will need heroic effort
  #(or at least some xml parsing) since rturk doesn't provide an
  #easy way to look at HIT qualifications)
  def test_abort_with_no_input
    assert_raises(Typingpool::Error::Shell){call_tp_assign}
  end

  def test_abort_with_no_template
    assert_tp_assign_abort_match([project_default[:title]], /Missing\b[^\n\r\f]*\btemplate/i)
  end

  def test_abort_with_bad_timespec
    assert_tp_assign_abort_match([project_default[:title], assign_default[:template], '--lifetime', '4u'], /can't convert/i)
  end

  def test_abort_with_bad_qualification
    assert_tp_assign_abort_match([project_default[:title], assign_default[:template], '--qualify', 'approval_rate &= 8'], /\bsense of --qualify.+\bunknown comparator\b/i)
    assert_tp_assign_abort_match([project_default[:title], assign_default[:template], '--qualify', 'fake_rate > 8'], /\bsense of --qualify\b.+unknown\b[^\n\r\f]*\btype\b/i)
  end

  def test_abort_with_bad_reward
    assert_tp_assign_abort_match([project_default[:title], assign_default[:template], '--reward', 'foo'], /sense of --reward/i)
  end

  def assert_tp_assign_abort_match(args, regex)
    assert_script_abort_match(args, regex) do |args|
      call_tp_assign(*args)
    end
  end

  def test_tp_assign
    skip_if_no_amazon_credentials('tp-assign integration test')
    skip_if_no_upload_credentials('tp-assign integration test')
    with_temp_readymade_project do |dir|
      begin
        tp_assign(dir)
        assign_time = Time.now
        config = config_from_dir(dir)
        project = temp_tp_dir_project(dir)
        setup_amazon(dir)
        results = nil
        refute_empty(results = Typingpool::Amazon::HIT.all_for_project(project.local.id))
        assert_equal(project.local.subdir('audio','chunks').to_a.size, results.size)
        assert_equal(Typingpool::Utility.timespec_to_seconds(assign_default[:deadline]), results[0].full.assignments_duration.to_i)
        #These numbers will be apart due to clock differences and
        #timing vagaries of the assignment.
        assert_in_delta((assign_time + Typingpool::Utility.timespec_to_seconds(assign_default[:lifetime])).to_f, results[0].full.expires_at.to_f, 60)
        keywords = results[0].at_amazon.keywords
        assign_default[:keyword].each{|keyword| assert_includes(keywords, keyword)}
        sandbox_csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
        refute_empty(assignment_urls = sandbox_csv.map{|assignment| assignment['assignment_url'] })
        assert(assignment_html = fetch_url(assignment_urls.first).body)
        assert_match(/\b20[\s-]+second\b/, assignment_html)
        assert_all_assets_have_upload_status(sandbox_csv, ['assignment'], 'yes')
      ensure
        tp_finish(dir)
      end #begin
      assert_empty(Typingpool::Amazon::HIT.all_for_project(project.local.id))
    end #with_temp_readymade_project do...
  end

   def test_uploads_audio_when_needed
     skip_if_no_amazon_credentials('tp-assign unuploaded audio integration test')
     skip_if_no_s3_credentials('tp-assign unuploaded audio integration test')
     with_temp_readymade_project do |dir|
       project_dir = temp_tp_dir_project_dir(dir)
       assert(File.exists? project_dir)
       assert(File.directory? project_dir)
       assert(project = temp_tp_dir_project(dir))
       csv = project.local.file('data', 'assignment.csv').as(:csv)
       assert_empty(csv.select{|assignment| working_url? assignment['audio_url']})
       csv.each!{|a| a['audio_uploaded'] = 'maybe'}
       assert_all_assets_have_upload_status(csv, ['audio'], 'maybe')
       begin
         tp_assign(dir)
         sandbox_csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
         assert_equal(csv.count, sandbox_csv.count)
         assert_equal(sandbox_csv.count, sandbox_csv.select{|assignment| working_url_eventually? assignment['audio_url'] }.count)
        assert_all_assets_have_upload_status(csv, ['audio'], 'yes')
       ensure
         tp_finish(dir)
       end #begin
     end #with_temp_readymade_project do...
   end

def test_fixing_failed_assignment_html_upload
  skip_if_no_amazon_credentials('tp-assign failed assignment upload integration test')
  skip_if_no_s3_credentials('tp-assign failed assignment upload integration test')
  with_temp_readymade_project do |dir|
    good_config_path = setup_s3_config(dir)
    reconfigure_readymade_project_in(good_config_path)
    project = temp_tp_dir_project(dir, Typingpool::Config.file(good_config_path))
    csv = project.local.file('data', 'assignment.csv').as(:csv)
    csv.each!{|a| a['audio_uploaded'] = 'maybe'}
    tp_make(dir, good_config_path)
    assert_all_assets_have_upload_status(csv, ['audio'], 'yes')
    bad_config_path = setup_s3_config_with_bad_password(dir)
    begin
      assert(project.local)
      get_assignment_urls = lambda{|csv| csv.map{|assignment| assignment['assignment_url'] }.select{|url| url } }
      assert_empty(get_assignment_urls.call(csv))
      exception = assert_raises(Typingpool::Error::Shell) do
        tp_assign(dir, bad_config_path)
      end #assert_raises...
      assert_match(/s3 operation fail/i, exception.message)
      sandbox_csv = project.local.file('data', 'sandbox-assignment.csv').as(:csv)
      refute_empty(get_assignment_urls.call(sandbox_csv))
      get_assignment_urls.call(sandbox_csv).each{|url| refute(working_url? url) }
      assert_all_assets_have_upload_status(sandbox_csv, ['assignment'], 'maybe')
      tp_assign(dir, good_config_path)
      get_assignment_urls.call(sandbox_csv).each{|url| assert(working_url_eventually? url) }
      assert_all_assets_have_upload_status(sandbox_csv, ['assignment'], 'yes')
    ensure
      tp_finish(dir, good_config_path)
    end #begin
  end #with_temp_readymade_project do...
end

def test_abort_on_config_mismatch
  skip_if_no_s3_credentials('tp-assign abort on config mismatch test')
  with_temp_readymade_project do |dir|
    config = config_from_dir(dir)
    good_config_path = setup_s3_config(dir, config, '.config_s3_good')
    reconfigure_readymade_project_in(good_config_path)
    assert(config.amazon.bucket)
    new_bucket = 'configmismatch-test'
    refute_equal(new_bucket, config.amazon.bucket)
    config.amazon.bucket = new_bucket
    bad_config_path = setup_s3_config(dir, config, '.config_s3_bad')
    success = false
    begin
      exception = assert_raises(Typingpool::Error::Shell) do
        tp_assign(dir, bad_config_path)
      end #assert_raises...
      assert_match(/\burls don't look right\b/i, exception.message)
      success = true
    ensure
      tp_finish(dir, good_config_path) unless success
    end #begin
  end #with_temp_readymade_project do...
end

end #TestTpAssign
