#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'uri'
require 'cgi'
require 'rturk'
require 'ostruct'
require 'timecop'

class TestAmazon < Typingpool::Test

  def test_amazon_base
    setup_result = Typingpool::Amazon.setup(:sandbox => true, :config => dummy_config)
    assert_match(/amazonaws/, setup_result)
    assert(Typingpool::Amazon.cache)
    assert_instance_of(PStore, Typingpool::Amazon.cache)
    assert_equal(dummy_config.cache, Typingpool::Amazon.cache.path)
    assert(full_rturk_hit = Typingpool::Amazon.rturk_hit_full('test'))
    assert_instance_of(RTurk::Hit, full_rturk_hit)
  end

  def test_amazon_question
    assert(question = dummy_question)
    assert_instance_of(Typingpool::Amazon::Question, question)
    assert_equal(question_url, question.url)
    assert_equal(question_html, question.html)
    assert_match(/Transcribe MP3 of/i, question.title)
    assert_match(/telephone conversation/i, question.description)
    assert_match(/\S/, question.annotation)
    assert(decoded_annotation = URI.decode_www_form(CGI.unescapeHTML(question.annotation)))
    decoded_annotation = Hash[*decoded_annotation.flatten]
    assert_match(/^http/i, decoded_annotation[Typingpool::Amazon::HIT.url_at])
    assert_match(/\S/, decoded_annotation[Typingpool::Amazon::HIT.id_at])
  end

  def test_amazon_hit_create
    with_dummy_typingpool_hit_or_skip('test_amazon_hit_create') do |hit, config|
      assert_equal(hit.full.external_question_url, dummy_question.url)
      assert_equal(config.assign.deadline, hit.full.assignments_duration.to_i)
      assert(rturk_hit = hit.at_amazon)
      assert_equal(dummy_question.annotation.to_s, CGI.escapeHTML(rturk_hit.annotation.to_s))
      assert_equal(dummy_question.title.strip, rturk_hit.title.strip)
      assert_equal(dummy_question.description.strip, rturk_hit.description.strip)
      assert_equal(config.assign.reward.to_f, rturk_hit.reward.to_f)
      assert_equal(config.assign.keywords.first.to_s, rturk_hit.keywords.first.to_s)
    end #with_dummy_hit
  end

  #fails to test all_reviewable or all_approved - those require a VCR fixture (TODO)
  def test_amazon_hit_retrievers
    with_dummy_typingpool_hit_or_skip('test_amazon_hit_retrievers') do |hit, config|
      assert(result = Typingpool::Amazon::HIT.with_ids([hit.id]))
      assert_equal(1, result.count)
      assert_equal(hit.id, result.first.id)
      assert(result = Typingpool::Amazon::HIT.all_for_project(hit.project_id))
      assert_equal(1, result.count)
      assert_equal(hit.id, result.first.id)
      assert(results = Typingpool::Amazon::HIT.all)
      assert(results.count > 0)
      assert(results = Typingpool::Amazon::HIT.all{|incoming_hit| incoming_hit.id == hit.id })
      assert_equal(1, results.count)
      assert_equal(hit.id, result.first.id)
    end #with_dummy_hit
  end

  #fails to properly test approved?, rejected?, submitted?, assignment - those require a VCR ficture (TODO)
  def test_amazon_hit_base
    with_dummy_typingpool_hit_or_skip('test_amazon_hit_base') do |hit, config|
      assert_instance_of(Typingpool::Amazon::HIT, hit)
      assert_match(/\S/, hit.id)
      assert_match(/^http/i, hit.url)
      assert_match(/\S/, hit.project_id)
      assert_match(/\S/, hit.project_title_from_url)
      assert(not(hit.approved?))
      assert(not(hit.rejected?))
      assert(not(hit.submitted?))
      assert(hit.ours?)
      assert_instance_of(Typingpool::Transcript::Chunk, hit.transcript)
      assert_kind_of(RTurk::Hit, hit.at_amazon)
      assert_instance_of(Typingpool::Amazon::HIT::Full, hit.full)
      assert_instance_of(Typingpool::Amazon::HIT::Assignment::Empty, hit.assignment)
    end #with_dummy_hit_or_skip
  end

  #fails to test external_question* methods
  def test_amazon_hit_full
    handle = 'test_amazon_hit_full'
    with_dummy_typingpool_hit_or_skip(handle) do |hit, config|
      time_travel(handle)
      assert(full = hit.full)
      assert_instance_of(Typingpool::Amazon::HIT::Full, full)
      [:id, :type_id].each{|attr| assert_match(/\S/, full.send(attr)) }
      assert(not(full.expired?))
      assert(not(full.expired_and_overdue?))
      assert_equal('Assignable', full.status)
      assert_match(/^http/i, full.external_question_url)
      [:assignments_completed, :assignments_pending].each{|attr| assert_match(/^\d+$/, full.send(attr).to_s) }
      assert_kind_of(Time, full.expires_at)
      assert_instance_of(Hash, full.annotation)
      assert_match(/^http/i, full.annotation[Typingpool::Amazon::HIT.url_at])
      assert_match(/\S/, full.annotation[Typingpool::Amazon::HIT.id_at])
      time_reset
    end #with_dummy_hit_or_skip
  end
  
  def time_travel(handle)
    time_path = File.join(fixtures_dir, "#{handle}_time.txt")
    if Typingpool::Test.record
      File.write(time_path, Time.now.to_i.to_s)
    elsif not(Typingpool::Test.live)
      File.exists? time_path or raise Typingpool::Error, "No time file at '#{time_path}'"
      Timecop.travel(Time.at(File.read(time_path).to_i))
    end
  end

  def time_reset
    Timecop.return
  end

  def test_amazon_hit_full_fromsearchhits
    with_dummy_typingpool_hit_or_skip('test_amazon_hit_full_fromsearchhits') do |hit, config|
      assert(full = hit.full)
      assert_instance_of(Typingpool::Amazon::HIT::Full, full)
      assert(hit2 = Typingpool::Amazon::HIT.all{|incoming_hit| incoming_hit.id == hit.id }.first)
      assert_equal(hit.id, hit2.id)
      assert(full2 = hit2.full)
      assert_instance_of(Typingpool::Amazon::HIT::Full::FromSearchHITs, full2)
      assert_equal(full.annotation.to_s, full2.annotation.to_s)
      [:assignments_completed, :assignments_pending, :id, :type_id, :status, :expires_at, :assignments_duration, :external_question_url].each{|attr| assert_equal(full.send(attr).to_s, full2.send(attr).to_s) }
    end #with_dummy_hit_or_skip
  end

  def test_handles_hits_without_external_question
    assert(dummy_response_xml = File.read(File.join(fixtures_dir, 'gethitresponse.xml')))
    dummy_http_response = OpenStruct.new
    dummy_http_response.body = dummy_response_xml
    assert(dummy_rturk_response = RTurk::GetHITResponse.new(dummy_http_response))
    assert(rturk_hit = RTurk::Hit.new(dummy_rturk_response.hit_id, dummy_rturk_response))
    assert(typingpool_full_hit = Typingpool::Amazon::HIT::Full.new(rturk_hit))
    refute(typingpool_full_hit.external_question_url)
    refute(typingpool_full_hit.external_question)
    assert(typingpool_hit = Typingpool::Amazon::HIT.new(rturk_hit))
    typingpool_hit.full(typingpool_full_hit)
    refute(typingpool_hit.ours?)
  end

  def test_handles_hits_with_broken_external_question
    config = self.config
    dummy_project = Typingpool::Project.new('dummy', config)
    url = dummy_project.remote.file_to_url(Typingpool::Project::Remote::S3.random_bucket_name(16,'dummy-missing-file-'))
    refute(working_url? url) if (Typingpool::Test.live || Typingpool::Test.record)
    with_dummy_typingpool_hit_or_skip('test_handles_hits_with_broken_external_question', url) do |hit, config|
      assert_equal(hit.full.external_question_url, url) if (Typingpool::Test.live || Typingpool::Test.record)
      refute(hit.full.external_question)
      refute(hit.full.external_question_param(hit.class.url_at))
   end #with_dummy....
  end

  #Lacks test for HIT::Assignment - needs VCR fixture (TODO)

  def question_html
    File.read(File.join(fixtures_dir, 'amazon-question-html.html'))
  end

  def question_url
    File.read(File.join(fixtures_dir, 'amazon-question-url.txt')).strip
  end

  def dummy_question(url=question_url)
    Typingpool::Amazon::Question.new(url, question_html)
  end

  def dummy_hit(config, url=question_url)
    Typingpool::Amazon::HIT.create(dummy_question(url), config.assign)
  end


  def with_dummy_typingpool_hit_or_skip(test_handle, url=question_url)
    config = self.config
    skip_if_no_amazon_credentials(test_handle, config)
    config.assign.reward = '0.01'
    config.assign.deadline = '1m'
    config.assign.lifetime = '2m'
    cache = Tempfile.new('typingpool_cache')
    with_vcr(test_handle, config, {
               :match_requests_on => [:method, Typingpool::App.vcr_core_host_matcher]
             }) do
      begin
        config.cache = cache.path
        Typingpool::Amazon.setup(:sandbox => true, :config => config)
        hit = dummy_hit(config, url)
        begin
          yield(hit, config)
        ensure
          hit.remove_from_amazon
        end #begin
      ensure
        cache.close
        cache.unlink
      end #begin
    end #with_vcr do...
  end
end #TestAmazon
