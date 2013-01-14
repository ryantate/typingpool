# Typingpool

Typingpool is an app for easily making transcripts of audio using
Amazon's labor marketplace, Mechanical Turk.

Typingpool is distributed as a Ruby gem. It is a made up of a handful
of scripts for users and a collection of library files for
developers. 

Typingpool also includes a collection of ERB templates for
generating Mechanical Turk assignments and the final transcript HTML
file.

## Dependencies

Typingpool depends on these command-line tools, which are not
included in the gem since they are external to Ruby:

  * [ffmpeg]     A powerhouse audio/video converter.
  * [libmp3lame] An mp3 encoder/decoder, used by ffmpeg.
  * [mp3splt]    An audio file-splitting utility.
  * [mp3wrap]    An audio file-merging utility.

## User overview

### Setup

After installing the gem and its dependencies, run tp-config from the
command line to create your config file (~/.typingpool). At the
prompts, you will need to supply your Amazon Web Services Access Key
ID and your Amazon Web Services Secret Access key.

The config file is in YAML format and may be customized using any
text editor. For more details on configuration options, see the
documentation for Typingpool::Config.

### Workflow

A typical workflow will use the bundled scripts in this order:

    tp-make -> tp-assign -> [wait] -> tp-review -> tp-finish

tp-review may be called repeatedly, until transcripts for all audio
chunks have been processed. Similarly, tp-assign may be called
repeatedly, for example to re-assign chunks rejected using tp-review,
or to re-assign chunks that have expired.

An alternate workflow would go like this:

    tp-make -> [manually upload assignments.csv to Amazon RUI] ->
      [wait] -> [approve/reject assignments via RUI] -> tp-collect ->
      tp-finish

### Examples

Typical usage scenario:

    tp-make 'Chad Interview' chad1.WMA chad2.WMA --unusual 'Hack Day,  
      Yahoo' --subtitle 'Phone interview re Yahoo Hack Day'
     
      # => Converting chad1.WMA to mp3
      # => Converting chad2.WMA to mp3
      # => Merging audio
      # => Splitting audio into uniform bits
      # => Uploading Chad Interview.00.00.mp3 to
             ryantate42.s3.amazonaws.com as Chad
             Interview.00.00.33ca7f2cceba9f8031bf4fb7c3f819f4.LHFJEM.mp3
      # => Uploading Chad Interview.01.00.mp3 to
             ryantate42.s3.amazonaws.com as Chad #
             Interview.01.00.33ca7f2cceba9f8031bf4fb7c3f819f4.XMWNYW.mp3
      # => Uploading Chad Interview.02.00.mp3 to
             ryantate42.s3.amazonaws.com as Chad #
             Interview.02.00.33ca7f2cceba9f8031bf4fb7c3f819f4.FNEIWN.mp3
      # => ... [snip]
      # => Done. Project at:
      # => /Users/ryantate/Desktop/Transcripts/Chad Interview
     
     
    tp-assign 'Chad Interview' interview/nameless --reward 1.00
      --deadline 90m --approval 6h --lifetime 2d
    
      # => Figuring out what needs to be assigned
      # => 85 assignments total
      # => 85 assignments to assign
      # => Deleting old assignment HTML from ryantate42.s3.amazonaws.com
      # => Uploading assignment HTML to ryantate42.s3.amazonaws.com
      # => Assigning
      # => Assigned 85 transcription jobs for $85
      # => Remaining balance: $115.00
    
    [Wait...]
     
     
    tp-review 'Chad Interview'
    
      # => Gathering submissions from Amazon
      # => Matching submissions with local projects
      # => 
      # => Transcript for: https://ryantate42.s3.amazonaws.com/
             Chad%20Interview.29.00.263d492275a81afb005c8231d8d8afdb.
              UEMOCN.mp3
      # => Project: Chad Interview: Phone interview re Yahoo Hack Day
      # => Submitted at: 2012-08-11 17:00:36 -0700 by A9S0AOAI8HO9P
      # => 
      # =>   Chad: ... so it had sort of some geek history. And the
      # =>   weather was really bad. But it was an indoor event,
      # =>   right? So people were staying indoors. And like very
      # =>   early... And there was all this really expensive gear
      # =>   that the BBC had. Like these cameras that guys were like
      # =>   riding around on and stuff, huge sound stage, bigger than
      # =>   the one we had in Sunnyvale.
      # =>   
      # =>   Two hours into the event, we heard this big lightning
      # =>   strike, because we were up on a hill in London. And all
      # =>   the lights went out and the roof opened up in the
      # =>   building. What we didn't know is the fire supression
      # =>   system in that building which got blown up by the
      # =>   lightning during a fire would cause the roof to open
      # =>   up. So we had all these geeks with equipment and all this
      # =>   BBC equipment and it was literally raining on them.
      # =>  
      # => (A)pprove, (R)eject, (Q)uit, [(S)kip]? (1/20) 
      
    a
     
      # => Approved. Chad Interview transcript updated.
      # => 
      # => Transcript for: https://ryantate42.s3.amazonaws.com/
             Chad%20Interview.30.00.263d492275a81afb005c8231d8d8afdb.
             RXNKRN.mp3
      # => Project: Chad Interview: Phone interview re Yahoo Hack Day
      # => Submitted at: 2012-08-11 17:00:58 -0700 by A9S0AOAI8HO9P
      # => 
      # =>   Blah blah blah blah okay I am done typing byeeeeeeee
      # => 
      # => (A)pprove, (R)eject, (Q)uit, [(S)kip]? (2/20) 
     
    r
     
      # => Rejection reason, for worker: 
    
    There's no transcription at all, just nonsense
    
      # => Rejected
      # => 
      # => Transcript for...
      # => ... [snip]
     
     tp-finish 'Chad Interview'
      
      # => Removing from Amazon
      # =>   Collecting all results
      # =>   Removing HIT 2GKMIKMN9U8PNHKK58NXL3SU4TCBSN (Reviewable)
      # =>   Removing from data/assignment.csv
      # =>   Removing from local cache  
      # =>   Removing HIT 2CFX2Q45UUKQ2HXZU8SNV8OG6CQBTC (Assignable)
      # =>   Removing from data/assignment.csv
      # =>   Removing from local cache
      # =>   Removing HIT 294EZZ2MIKMNNDP1LAU8WWWXOEI7O0...
      # =>   ... [snip]
      # =>   Removing Chad Interview.00.00.
               263d492275a81afb005c8231d8d8afdb.ORSENE.html from 
               ryantate42.s3.amazonaws.com
      # =>   Removing Chad Interview.01.00...
      # =>   ... [snip]
      # =>   Removing Chad Interview.00.00.
               263d492275a81afb005c8231d8d8afdb.RNTVLN.mp3 from
               ryantate42.s3.amazonaws.com
      # =>   Removing Chad Interview.01.00....
      # =>   ... [snip]

### Output

The final output of Typingpool is a project directory containing a
transcript file.

The transcript file is HTML with audio chunks embedded alongside each
associated transcript chunk.

The transcript file is called transcript.html when complete. A
partial transcript file is called transcript_in_progress.html.

The project directory also includes supporting files, including a CSV
data file used to store raw transcript chunks, Amazon Mechanical Turk
HIT information, and other metdata; Javscript code that swaps in
Flash players on browsers that don't support mp3 files in audio tags;
the original audio files and the audio chunks generated from them;
and a CSS file.

The directory is laid out like so:

     Chad Interview/
       -> transcript.html | transcript_in_progress.html
       -> audio/
           -> chunks/
               -> Chad Interview.00.00.mp3
               -> Chad Interview.01.00.mp3
               -> ... [snip]
           -> originals/
               -> chad1.WMA
               -> chad2.WMA
       -> data/
           -> assignment.csv
           -> id.txt
           -> subtitle.txt
       -> etc/
           -> audio-compat.js
           -> transcript.css
           ->  About these files - readme.txt
           -> player/
               -> audio-player.js
               -> license.txt
               -> player.swf
 
You may safely edit the files transcript.html, etc/transcript.css,
and data/subtitle.txt, and you may safely delete the files in
audio/originals and any .txt files in etc/. Editing or deleting other
files may interfere with the operation of Typingpool or render the
transcript inoperative. Do not edit transcript_in_progress.html as
your changes will be overwritten if/when the transcript is next
updated.


### Workflow (additional)

When you've rejected some submissions in tp-review and need to
re-assign these chunks to be transcribed, simply re-run tp-assign
with the name of your project. You may select the same template,
reward, deadlines, etc., or pick new ones. tp-assign will be careful
not to re-assign chunks for which you have approved a transcript, or
which are pending on Mechanical Turk.

When some chunks previously assigned via tp-assign have expired
without attracting submissions, simply re-run tp-assign as described
above to re-assign these chunks. Consider increasing the dollar
amount specified in your --reward argument.

When some chunks previously assigned via tp-assign have been
submitted by workers but not approved or rejected in time for the
approval deadline (assign/approval in your config file or --approval
as passed to tp-assign), Mechanical Turk has automatically approved
these submissions for you and you'll need to run tp-collect to
collect them.

When you want to cancel outstanding assignments, for example because
you realize you supplied the wrong parameter to tp-assign, simply run
tp-finish with the name of your project. If your assignments have
already attracted submissions, you may be prompted to run tp-review
first.

When tp-make, tp-assign, or tp-finish unsuccessfully attempts an
upload, deletion, or Amazon command, simply re-run the script with
the same arguments to re-attempt the upload, deletion or Amazon
command. Typingpool carefully records which network operations it is
attempting and which network operations have completed. It can
robustly handle network errors, including uncaught exceptions.

When you want to preview your assignments, run tp-assign with the
--sandbox option and with --qualify 'rejection_rate < 100' (to make
sure you qualify to view your own HITs). Then visit
http://workersandbox.mturk.com and find your assignments (a seach for
"mp3" works if you left mp3 set as a keyword in your config
file). When you are done previewing, run tp-finish with the name/path
of your project and the --sandbox option.


### Maintenance

  * [cache]     If the cache file grows too large, you'll need to delete
                it manually. It may be safely deleted as long as no
                Typingpool scripts are running. Its location is
                specified in the 'cache' param in the config
                file. (The config file is at ~/.typingpool and the
                cache, by default, is at ~/.typingpool.cache.)

                Typingpool takes no steps to limit the size of the
                cache file. It prunes the cache of project-specific
                entries when you run tp-finish on a project, but the
                cache may grow large if you work on many active
                projects in parallel, or if you fail to run tp-finish
                on projects when you are done with them.

  * [tp-finish] You should run tp-finish PROJECT each time you finish
                a project, where PROJECT may be either the project
                name or path. Assuming you have no submissions pending
                or awaiting approval, this clears all traces of the
                project from Amazon Mechanical Turk, from Amazon S3 or
                your SFTP server, and from the local cache. This will
                keep your local cache from balooning in size and will
                minimize your S3 charges or SFTP disk usage. It will
                also help Typingpool scripts run faster by reducing
                the number of HITs you have on Amazon Mechanical Turk;
                many Typingpool operations involve iterating through
                all of your HITs.


### See also

 * Run any script with the --help options for further details on how
   to run the script.

 * See the docs for Typingpool::Config for details of the config
   file format.

 * See Amazon's Mechanical Turk documentation for guides and
   overviews on how Mechanical Turk works.

 * See the documentation on ffmpeg and related libraries for clues
   as to how to make Typingpool support additional file
   formats. Typingpool can work with any file format that ffmpeg can
   convert to mp3 (libmp3lame).


## Developer overview

Views, used for the final transcript and for rendering HTML
assignments for Amazon Mechanical Turk workers, are contained in a
series of templates in lib/typingpool/templates, particularly
transcript.html.erb and assignment/*. The control layer lives in the
App class (lib/typingpool/app.rb) and within the individual
scripts. The models constitute the other Typingpool classes,
including most importantly and in rough order of importance the
Project, Transcript, Amazon, Config and Filer classes (the latter of
interest mainly because of Filer::Audio, which handles splitting,
merging, and conversion).

The models in particular, along with the App class, are underdeveloped
and not particularly clear or fully thought through. The Transcript
model, for example, should almost certainly be folded into the Project
model. Dividing Project into Project::Local and Project::Remote only
makes sense on a superficial level; Project::Remote could probably be
its own class or even part of Utility. Amazon will probably be simpler
if I can get some patches into RTurk, and Amazon::HIT should probably
be integrated more closely with Project.

One of the most frustrating things about the code is that there are so
many subtly different ways a "chunk" of a transcript/project is
represented: As a simple hash derived from a row in
data/assignment.csv within a project folder, as an Amazon::HIT, as a
Transcription::Chunk, as an audio file on a remote server, and as a
local audio file (which has a different name from the remote file). So
in future versions I'll probably reduce the number of different ways
to represent a chunk.

Also in the future, it's very likely that App will evolve from a
simple collection of class methods into a real class with a simple
set of instance methods called in a particular order by a "run"
method or similar. Subclasses for particular scripts/commands will
then override these methods.


### Examples

The most comprehensive examples of how the Typingpool classes
actually work and interact are the tp-* scripts themselves, in
particular tp-make, tp-assign, tp-review, and tp-finish.

More concise examples follow below, to give you a sense of what the
various classes actually do:

```ruby
 require 'typingpool'
 
 #new Project instance
 project = Typingpool::Project.new('Chad Interview')
 
 #check if project exists on disk
 unless project.local
   #make a skeleton project folder in Config#transcripts dir
   project.create_local 
   #make subtitle record in project folder
   project.local.subtitle = 'Interview about Hack Day Jan 21' 
 end
 
 id = project.local.id
 
 #Wrap file in Typingpool::Filer
 wma = Typingpool::Filer::Audio.new('/foo/bar.wma')
 
 #convert file to mp3
 mp3 = wma.to_mp3
 other_mp3 = Typingpool::Filer::Audio.new('/foo/bar2.wma').to_mp3
 
 #merge audio
 combined_mp3 = Typingpool::Filer::Files::Audio.new([mp3,
   other_mp3]).merge(Typingpool::Filer.new('/foo/combined.mp3')
 
 #split audio every 1 minute
 chunks = combined_mp3.split('1.00')
 
 #upload mp3s
 urls = project.remote.put(chunks.to_streams,
   project.create_remote_names(chunks))
 
 #remove mp3s
 project.remote.remove_urls(urls)
 
 #new Template instance
 template = Typingpool::Template::Assignment.from_config('interview/nameless')
 html = template.render({
                         'audio_url' => urls[0],
                         'unusual' => ['Hack Day', 'Yahoo', 'Atlassian'],
                         'chunk_minutes' => 1,
                         'project_id' => project.local.id
                         })
 
 question = Typingpool::Amazon::Question.new(urls[0], html)
 
 Typingpool::Amazon.setup
 
 #Assign a transcription job (1 chunk)
 hit = Typingpool::Amazon::HIT.create(question, Typingpool::Config.file.assign)
 
 #Find all Typingpool HITs on Amazon Mechanical Turk
 all = Typingpool::Amazon::HIT.all
 #Find all reviewable Typingpool HITs
 reviewable = Typingpool::Amazon::HIT.all_reviewable
 #Find all approved Typingpool HITs
 approved = Typingpool::Amazon::HIT.all_approved
 #Find all HITs for our project
 project_hits = Typingpool::Amazon::HIT.all_for_project(project.local.id)
 #Filter all HITs (not just Typingpool HITs) arbitrarily
 safe_to_delete = Typingpool::Amazon::HIT.all{|hit| hit.ours? && hit.full.expired_and_overdue? }
 #Filter all approved HITs arbitrarily
 ready_for_judgment = Typingpool::Amazon::HIT.all_reviewable{|hit| hit.submitted? && hit.ours? }
 
 #Approve a HIT
 ready_for_judgment[0].at_amazon.approve! #at_amazon is an rturk instance
 #Reject a HIT
 ready_for_judgment[1].at_amazon.reject!('Your transcription is just random gibberish')
 #Delete a HIT from Amazon
 safe_to_delete[0].remove_from_amazon

 #Get text of transcript chunk (Typingpool::Transcript::Chunk)
 transcript_chunk = approved[0].transcript
 puts transcript_chunk.body
 #Get formmated text of transcript chunk
 puts transcript_chunk.body_as_text
 #Get transcript chunk as HTML
 puts transcript_chunk.body_as_html
 #Get transcript chunk metadata
 puts "--#{transcript_chunk.url} (audio at #{transcript_chunk.offset})"
```

##Author

Ryan Tate - ryantate@ryantate.com

##License

Copyright (c) 2011-2013 Ryan Tate. Released under the terms of the MIT
license. See LICENSE for details.