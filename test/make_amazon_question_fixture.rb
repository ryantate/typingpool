#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'
require 'fileutils'

class MakeAmazonQuestion < Typingpool::Test::Script
  def test_make_amazon_question_fixture
    with_temp_transcripts_dir do |dir|
      tp_make(dir)
      template = Typingpool::Template::Assignment.from_config(assign_default[:template], config_from_dir(dir))
      assignment = transcripts_dir_project(dir).local.file('data', 'assignment.csv').as(:csv).read.first
      question_html = template.render(assignment)
      question_url = 'http://example.com/assignments/101.html'
      assert_match(question_html, /\S/)
      assert_match(question_url, /http/i)
      File.open(File.join(fixtures_dir, 'amazon-question-html.html'), 'w'){|f| f << question_html}
      File.open(File.join(fixtures_dir, 'amazon-question-url.txt'), 'w'){|f| f << question_url}
    end #with_temp_transcripts_dir
    add_goodbye_message("Amazon question fixtures created.")
  end
end #MakeAmazonQuestion
