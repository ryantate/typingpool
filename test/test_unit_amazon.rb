#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'
require 'uri'
require 'cgi'

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
    with_dummy_hit_or_skip('test_amazon_hit_create') do |hit, config|
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
    with_dummy_hit_or_skip('test_amazon_hit_retrievers') do |hit, config|
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
    with_dummy_hit_or_skip('test_amazon_hit_base') do |hit, config|
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
    with_dummy_hit_or_skip('test_amazon_hit_full') do |hit, config|
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
    end #with_dummy_hit_or_skip
  end

  def test_amazon_hit_full_fromsearchhits
    with_dummy_hit_or_skip('test_amazon_hit_full_fromsearchhits') do |hit, config|
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

  #Lacks test for HIT::Assignment - needs VCR fixture (TODO)

  def question_html
    File.read(File.join(fixtures_dir, 'amazon-question-html.html'))
  end

  def question_url
    File.read(File.join(fixtures_dir, 'amazon-question-url.txt')).strip
  end

  def dummy_question
    Typingpool::Amazon::Question.new(question_url, question_html)
  end

  def dummy_hit(config)
    Typingpool::Amazon::HIT.create(dummy_question, config.assign)
  end

  def with_dummy_hit_or_skip(skipping_what)
    config = self.config
    skip_if_no_amazon_credentials(skipping_what, config)
    config.assign.reward = '0.01'
    cache = Tempfile.new('typingpool_cache')
    begin
      config.cache = cache.path
      Typingpool::Amazon.setup(:sandbox => true, :config => config)
      hit = dummy_hit(config)
      begin
        yield(hit, config)
      ensure
        hit.remove_from_amazon
      end #begin
    ensure
      cache.close
      cache.unlink
    end #begin
  end
end #TestAmazon
