#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestTranscript < Typingpool::Test

  def test_transcript_base
    assert(transcript = Typingpool::Transcript.new(project_default[:title]))
    assert_equal(project_default[:title], transcript.title)
    assert_equal(0, transcript.count)
    dummy_chunks = self.dummy_chunks
    assert(transcript = Typingpool::Transcript.new(project_default[:title], dummy_chunks))
    assert_equal(dummy_chunks.count, transcript.count)
    assert_respond_to(transcript, :each)
    transcript.each_with_index do |chunk, i| 
      assert_respond_to(chunk, :body)
      assert_equal(dummy_chunks[i].body, chunk.body)
      assert_equal(chunk.body, transcript[i].body)
    end #transcript.each_with_index do...
    assert(transcript = Typingpool::Transcript.new(project_default[:title]))
    assert_equal(0, transcript.count)
    assert_respond_to(transcript, :add_chunk)
    dummy_chunks.each{|chunk| transcript.add_chunk(chunk) }
    assert_equal(dummy_chunks.count, transcript.count)
    random_index = rand(dummy_chunks.count)
    assert_equal(dummy_chunks[random_index].body, transcript[random_index].body)
  end

  def test_transcript_chunks
    dummy_assignments.each do |assignment|
      assert(chunk = Typingpool::Transcript::Chunk.new(assignment['transcript']))
      assert_equal(assignment['transcript'], chunk.body)
      chunk.worker = assignment['worker']
      assert_equal(assignment['worker'], chunk.worker)
      chunk.project = assignment['project_id']
      assert_equal(assignment['project_id'], chunk.project)
      chunk.hit = assignment['hit_id']
      assert_equal(assignment['hit_id'], chunk.hit)
      url_populated = %w(offset offset_seconds filename filename_local)
      url_populated.each{|attr| assert_nil(chunk.send(attr.to_sym)) }
      chunk.url = assignment['audio_url']
      assert_equal(assignment['audio_url'], chunk.url)
      url_populated.each{|attr| refute_nil(chunk.send(attr.to_sym)) }
      matches = chunk.offset.match(/^(\d+):(\d+)$/)
      assert_equal(((matches[1].to_i * 60) + matches[2].to_i), chunk.offset_seconds)
      refute_equal(chunk.filename, chunk.filename_local)
      original_newline_count = chunk.body_as_text.scan(/\n/).count
      chunk.body = chunk.body + "\n\r\f" + ('foo bar baz' * 100) 
      refute_match(/\r/, chunk.body_as_text) unless $/.match(/\r/)
      assert_equal(original_newline_count + 2, chunk.body_as_text.scan(/\n/).count)
      original_p_count = chunk.body_as_html.scan(/<p>/i).count
      chunk.body = chunk.body + "One & two\n\n...and 3 < 4."
      refute_match(/\s&\s/, chunk.body_as_html)
      refute_match(/\s<\s/, chunk.body_as_html)
      assert_equal(original_p_count + 1, chunk.body_as_html.scan(/<p>/i).count)
    end
  end

  def dummy_chunks
    dummy_assignments.map do |assignment|
      chunk = Typingpool::Transcript::Chunk.new(assignment['transcript'])
      chunk.worker = assignment['worker']
      chunk.project = assignment['project_id']
      chunk.hit = assignment['hit_id']
      chunk.url = assignment['audio_url']
      chunk
    end #dummy_assignments.map do...
  end

  def dummy_assignments
    Typingpool::Filer::CSV.new(File.join(fixtures_dir, 'transcript-chunks.csv')).read
  end

end #TestTranscript
