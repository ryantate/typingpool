#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'fileutils'

class TestFiler < Typingpool::Test

  def test_filer_base
    path = File.join(fixtures_dir, 'config-1')
    assert(filer = Typingpool::Filer.new(path))
    assert_equal(path, "#{filer}")
    assert(text = filer.read)
    assert_match(/^amazon:\n/, text)
    assert_match(/transcripts: ~\/Documents\/Transcripts\//, text)
    assert_match(/- mp3\s*$/, text)
    assert_equal(fixtures_dir, filer.dir.path)
    in_temp_dir do |dir|
      path = File.join(dir, 'filer-temp')
      assert(filer = Typingpool::Filer.new(path))
      assert_instance_of(Typingpool::Filer::CSV, filer_csv = filer.as(:csv))
      assert_equal(filer.path, filer_csv.path)
      assert_nil(filer.read)
      data = "foo\nbar\nbaz."
      assert(filer.write(data))
      assert_equal(data, filer.read)
      assert(path = filer.mv!(File.join(dir, 'filer-temp-2')))
      assert(File.exists? filer.path)
      assert_equal('filer-temp-2', File.basename(filer.path))
    end #in_temp_dir
  end

  def test_filer_csv
    path = File.join(fixtures_dir, 'tp_review_sandbox-assignment.csv')
    assert(filer = Typingpool::Filer::CSV.new(path))
    assert_equal(path, "#{filer}")
    assert(data = filer.read)
    assert_instance_of(Array, data)
    assert_instance_of(Hash, data.first)
    assert_respond_to(filer, :each)
    assert_respond_to(filer, :map)
    assert_respond_to(filer, :select)
    assert(data.first['audio_url'])
    assert_match(/^https?:\/\/\w/, data.first['audio_url'])
    assert(filer.select{|r| r['audio_url'] }.count > 0)
    in_temp_dir do |dir|
      path = File.join(dir, 'filer-temp')
      assert(filer2 = Typingpool::Filer::CSV.new(path))
      assert_equal([], filer2.read)
      assert(filer2.write(data))
      assert_equal(Typingpool::Filer.new(filer.path).read, Typingpool::Filer.new(filer2.path).read)
      assert_equal(filer.count, filer2.count)
      filer2.each! do |row|
        row['audio_url'] = row['audio_url'].reverse
      end
      rewritten = Typingpool::Filer.new(filer2.path).read
      assert(Typingpool::Filer.new(filer.path).read != rewritten)
      keys = filer2.first.keys
      filer2.write_arrays(filer2.map{|row| keys.map{|key| row[key] } }, keys)
      assert_equal(rewritten, Typingpool::Filer.new(filer2.path).read)
    end #in_temp_dir
  end

  #This might be more comprehensive if it looped and ran once with
  #Encoding set to 'US-ASCII' - but we'd have to be carefult to reset
  #Encoding back to orig value. For now I just run ruby -E 'US-ASCII'
  #test_unit_filer.rb now and again.
  def test_filer_csv_utf8
    path = File.join(fixtures_dir, 'tp_review_sandbox-assignment.csv')
    assert(filer = Typingpool::Filer::CSV.new(path))
    assert(data = filer.read)
    assert_instance_of(Array, data)
    assert_instance_of(Hash, data.first)
    in_temp_dir do |dir|
      path = File.join(dir, 'filer-temp')
      assert(filer2 = Typingpool::Filer::CSV.new(path))
      assert_equal([], filer2.read)
      assert(filer2.write(data))
      assert_equal(Typingpool::Filer.new(filer.path).read, Typingpool::Filer.new(filer2.path).read)
      refute_empty(assignments = filer2.read)
      assert(assignment = assignments.pop)
      assert(assignment['transcript'] = File.read(File.join(fixtures_dir, 'utf8_transcript.txt'), :encoding => 'UTF-8'))
      assignments.push(assignment)
      assert(filer2.write(assignments)) 
      refute_empty(filer2.read) #will throw ArgumentError: invalid byte sequence in US-ASCII in degenerate case
    end #in_temp_dir
  end

  def test_filer_audio
    mp3 = Typingpool::Filer::Audio.new(files_from(File.join(audio_dir, 'mp3')).first)
    wma = Typingpool::Filer::Audio.new(files_from(File.join(audio_dir, 'wma')).first)
    assert(mp3.mp3?)
    assert(not(wma.mp3?))
    in_temp_dir do |dir|
      [mp3, wma].each do |file|
        FileUtils.cp(file, dir)
      end
      mp3 = Typingpool::Filer::Audio.new(File.join(dir, File.basename(mp3)))
      wma = Typingpool::Filer::Audio.new(File.join(dir, File.basename(wma)))
      dest = Typingpool::Filer::Audio.new(File.join(dir, 'filer-temp.mp3'))
      assert(converted = wma.to_mp3(dest))
      assert_equal(dest.path, converted.path)
      assert(wma.bitrate >= 30)
      assert(wma.bitrate <= 40)
      assert(converted.bitrate)
      assert(converted.mp3?)
      assert(chunks = mp3.split('0.25', 'filer-temp', Typingpool::Filer::Dir.new(dir)))
      assert(not(chunks.to_a.empty?))
      assert_equal(3, chunks.count)
      chunks.each{|chunk| assert(File.exists? chunk) }
      assert(chunks.first.offset)
      assert_match(/0\.00\b/, chunks.first.offset)
      assert_match(/0\.25\b/, chunks.to_a[1].offset)
    end #in_temp_dir
  end

  def files_from(dir)
    Dir.entries(dir).map{|entry| File.join(dir, entry) }.select{|path| File.file? path }.reject{|path| path.match(/^\./) }
  end

  def test_filer_files_base
    file_selector = /tp[_-]collect/
    dir = fixtures_dir
    files = files_from(dir).select{|path| path.match(file_selector) }
    dir = File.join(fixtures_dir, 'vcr')
    files.push(*files_from(dir).select{|path| path.match(file_selector) })
    assert(files.count > 0)
    assert(filer = Typingpool::Filer::Files.new(files.map{|path| Typingpool::Filer.new(path) }))
    assert_equal(filer.files.count, files.count)
    assert_respond_to(filer, :each)
    assert_respond_to(filer, :select)
    assert_respond_to(filer, :map)
    assert_instance_of(Typingpool::Filer::Files::Audio, filer.as(:audio))
  end

  def test_filer_files_audio
    mp3s = files_from(File.join(audio_dir, 'mp3')).map{|path| Typingpool::Filer::Audio.new(path) }
    wmas = files_from(File.join(audio_dir, 'wma')).map{|path| Typingpool::Filer::Audio.new(path) }
    assert(mp3s.count > 0)
    assert(wmas.count > 0)
    assert(filer_mp3 = Typingpool::Filer::Files::Audio.new(mp3s))
    assert(filer_wma = Typingpool::Filer::Files::Audio.new(wmas))
    assert_equal(mp3s.count, filer_mp3.files.count)
    assert_equal(wmas.count, filer_wma.files.count)
    in_temp_dir do |dir|
      dest_filer = Typingpool::Filer::Dir.new(dir)
      assert(filer_conversion = filer_wma.to_mp3(dest_filer))
      assert_equal(filer_wma.files.count, filer_conversion.files.count)
      assert_equal(filer_wma.files.count, filer_conversion.select{|file| File.exists? file }.count)
      assert_equal(filer_wma.files.count, filer_conversion.select{|file|  file.mp3? }.count)
      assert_equal(filer_conversion.files.count, dest_filer.files.count)
      temp_path = File.join(dir, 'temp.mp3')
      assert(filer_merged = filer_mp3.merge(Typingpool::Filer.new(temp_path)))
      assert(File.size(filer_merged) > File.size(filer_mp3.first))
      assert(filer_merged.mp3?)
      assert(filer_merged.path != filer_mp3.first.path)
      assert(filer_merged.path != filer_mp3.to_a[1].path)
    end #in_temp_dir
  end

  def test_filer_dir
    assert(dir = Typingpool::Filer::Dir.new(fixtures_dir))
    assert_equal(fixtures_dir, dir.path)
    dir2_path = File.join(fixtures_dir, 'doesntexist')
    assert(not(File.exists? dir2_path))
    assert(dir2 = Typingpool::Filer::Dir.new(dir2_path))
    in_temp_dir do |dir|
      dir3_path = File.join(dir, 'filer-dir-temp')
      assert(not(File.exists? dir3_path))
      assert(dir3 = Typingpool::Filer::Dir.create(dir3_path))
      assert(File.exists? dir3_path)
      assert_instance_of(Typingpool::Filer::Dir, dir3)
      assert_nil(dir2 = Typingpool::Filer::Dir.named(File.basename(dir2_path), File.dirname(dir2_path)))
      assert(dir3 = Typingpool::Filer::Dir.named(File.basename(dir3_path), File.dirname(dir3_path)))
      assert_instance_of(Typingpool::Filer::Dir, dir3)
      assert_equal(dir3_path, dir3.to_s)
      assert_equal(dir3_path, dir3.to_str)
      assert(filer = dir3.file('doesntexist'))
    end #in_temp_dir
    assert(filer = dir.file('vcr', 'tp-collect-1.yml'))
    assert(File.exists? filer.path)
    assert_instance_of(Typingpool::Filer, filer)
    assert(csv = dir.file('tp_collect_sandbox-assignment.csv').as(:csv))
    assert(File.exists? csv.path)
    assert_instance_of(Typingpool::Filer::CSV, csv)
    dir4 = Typingpool::Filer::Dir.new(audio_dir)
    assert(audio = dir4.file('mp3', 'interview.1.mp3').as(:audio))
    assert(File.exists? audio.path)
    assert_instance_of(Typingpool::Filer::Audio, audio)
    assert(filers = dir.files)
    assert(not(filers.empty?))
    assert_kind_of(Typingpool::Filer, filers.first)
    assert(File.exists? filers.first.path)
    dir_files = Dir.entries(dir.path).map{|entry| File.join(dir.path, entry)}.select{|path| File.file?(path) }.reject{|path| File.basename(path).match(/^\./) }
    assert_equal(dir_files.count, filers.count)
    assert(dir5 = dir.subdir('vcr'))
    assert(File.exists? dir5.path)
    assert_instance_of(Typingpool::Filer::Dir, dir5)
  end
end #TestFiler
