#!/usr/bin/env perl

###Script that takes audio file paths and some metadata and creates a
###local and web server folder suitable for creating an audio
###transcription assignment on Amazon Mechanical Turk.

##TODO
#Verify all URLs to make sure there are no 404s

use strict;
use warnings;

use File::Temp qw(tempfile tempdir);
use File::Path qw(remove_tree);
use File::Copy;
use File::Spec;
use POSIX qw(floor);
use Text::CSV;
use String::Random;
use YAML ();
use Getopt::Long;

my $Dialoger = '/Applications/CocoaDialog.app/Contents/MacOS/CocoaDialog';
Getopt::Long::Configure(qw(bundling ignore_case));

my (%opt, @files, @voices, @unusual, $subtitle, $time, $project_name);
GetOptions(
    'help' => \$opt{help},
    'file=s' => \@files,
    'title=s' => \$project_name,
    'chunks=s' => \$time,
    'subtitle=s' => \$subtitle,
    'voice=s' => \@voices,
    'unusual=s' => \@unusual,
    'moveorig' => \$opt{moveorig},
    );
my $usage = "USAGE: at-assign --file foo.mp3 [--file bar.mp3...] --title Foo --chunks 1:00 [--subtitle 'Foo telephone interview about Yahoo Hack Day'][--voice 'John Foo' [--voice 'Sally Bar, Female interiewer with British accent'...]...][--unusual 'Yahoo' --unusual 'Hack Day' --unusual 'Sunnyvale, Chad Dickerson, Zawodny'][--moveorig]\n";
die $usage if $opt{help};
my $name_via_command_line;
$name_via_command_line = 1 if $project_name;

@files = @ARGV if not @files;
@files or error_bye("Drag audio files onto the icon");

#Need files in proper order before joining them
@files = sort { filepath_sortable($a) cmp filepath_sortable($b) } @files;
#Need file extensions so we know what files need to be converted to mp3
filebase_split($_) or error_bye("You need a file extension on the file '$_'") foreach @files;
#Escape file names so they can safely be passed to shell within single quotes 
shell_safe($_) or error_bye("Unsafe file name", $_) foreach @files;

my %config = config_file();
$config{$_} or error_bye("Required param '$_' missing from config file", "$ENV{HOME}/.audibleturk") foreach qw(scp url app);
#my @fails = $config{scp} =~ /[^\w\s_\@\/\.\:\-]+/g;
#print "DEBUG fail $_\n" foreach @fails;
$config{scp} =~ /^[\w\s_\@\/\.\:\+\-]+$/ or error_bye("Unexpected scp format in config file", "$ENV{HOME}/.audibleturk");

foreach (qw(local app)){
    if ($config{$_}) {
	$config{$_} =~ s/^~(\/?)/$ENV{HOME}$1/;
	$config{$_} = "$ENV{HOME}/$config{$_}" if $config{$_} =~ /^[^\/]/;
	$config{$_} =~ s/\/$//;
    }
}

$config{local} ||= "$ENV{HOME}/Desktop";

foreach (qw(scp url local app)){
    $config{$_} =~ s/\s+$//;
    $config{$_} =~ s/\/$//;
}

shell_safe($config{$_}) or error_bye("Unsafe $_ dir name", $config{$_}) foreach qw(local app);
if (exists $config{randomize}){
    $config{randomize} = 0 if $config{randomize} =~ /\bfalse\b/i;
    $config{randomize} = 0 if $config{randomize} =~ /\bno\b/i;
    $config{randomize} = 0 if $config{randomize} =~ /\b0\b/;
    $config{randomize} = 0 if not defined $config{randomize}
}
else {
    $config{randomize} = 1;
}

#Get split interval
my $default_interval = $config{split} || '1:00';
$default_interval =~ /^[\d\:\s\.]+$/ or error_bye("Unexpected format to default split interval '$default_interval'");
my $min_dot_seconds;
$min_dot_seconds = to_min_seconds($time) if $time;
until ($min_dot_seconds) {
  my $dialog_input = `$Dialoger standard-inputbox --title "Length" --no-newline --informative-text "Split audio every (hh:mm:ss)" --text '$default_interval'`;
  my ($button, $time) = split /\n/, $dialog_input, 2;
  $button == 1 or exit;
  $min_dot_seconds = to_min_seconds($time) or error_box("Did not understand the time '$time'");
  config_file('split' => $time) if $min_dot_seconds;
}


#Get base name for mp3s we'll be outputting
my ($default_name) = filebase_split(filepath_base($files[0]));
$default_name =~ s/(\w+)(\.)?\d+(\.mono)?$/$1/;
until ($project_name && init_project_dir($project_name)) {
  my $filled_in_name = $project_name || $default_name;
  shell_safe($filled_in_name) or error_bye("Potentially unsafe name encountered: $filled_in_name");
  my $dialog_input = `$Dialoger standard-inputbox --title "Name" --no-newline --informative-text "Base name for mp3s:" --text '$filled_in_name'`;
  my $button;
  ($button, $project_name) = split /\n/, $dialog_input, 2;
  $button == 1 or exit;
  $project_name =~ s/\s/_/g;
  $project_name =~ s/[^\w_-]//g;
  if (not($project_name =~ /\w/)) {
    error_box('Name must contain one letter or number');
    $project_name = '';
  }
}

sub init_project_dir{
  my ($project_name) = @_;

  if (mkdir "$config{local}/$project_name") {
    mkdir "$config{local}/$project_name/$_" or error_bye("Failed to create folder", "$_ ($!)") foreach qw(audio csv originals etc);
    return 1;
  } else {
    if ($! =~ /file exists/i) {
      error_box("Name '$project_name' taken, please choose another", "Folder already exists at $config{local}/$project_name");
      return 0;
    } else {
      error_bye("Failed to create folder", "$config{local}/$project_name: $!");
    }
  }
}

#Get optional subtitle, write to etc/
if ($subtitle) {
  write_subtitle($subtitle);
} elsif (not $name_via_command_line) {
  my $dialog_input =  `$Dialoger standard-inputbox --title "Subtitle" --no-newline --informative-text "Subtitle to appear at top of $project_name transcription. Date, meeting location or other notes. Optional."`;
  my $button;
  ($button, $subtitle) = split /\n/, $dialog_input, 2;
  if ($subtitle && $button == 1) {
    write_subtitle($subtitle)
  }
}

sub write_subtitle{
  my ($subtitle) = @_;
  return if not defined $subtitle;
  open(my $fh, '>', "$config{local}/$project_name/etc/subtitle.txt") or error_bye("Error writing subtitle", "$config{local}/$project_name/etc/subtitle.txt: $!");
  print $fh $subtitle;
  close $fh;
}

#Copy CSS default to etc/
copy("$config{app}/www/transcript.css", "$config{local}/$project_name/etc/transcript.css") or error_bye("Could not copy CSS template", "Could not copy 'transcript.css' to 'etc/': $!");

#Copy Javascript files to etc/
mkdir("$config{local}/$project_name/etc/player") or error_bye("Failed to create folder", "etc/player ($!)");
copy("$config{app}/www/player/$_", "$config{local}/$project_name/etc/player/$_") or error_bye("Could not copy $_ to etc/player/ ($!)") foreach ('license.txt', 'player.swf','audio-player.js');
copy("$config{app}/www/audio-compat.js", "$config{local}/$project_name/etc/audio-compat.js") or error_bye("Could not copy 'audio-compat.js' to 'etc/': $!");

#Copy audio files to 'originals' folder
foreach my $file (@files){
    my $base = filepath_base($file);
    my $new_path = "$config{local}/$project_name/originals/$base";
    if ($opt{moveorig}){
	move($file, $new_path) or error_bye ("Could not move original audio file", "Could not move $file to $new_path: $!");
    }
    else {
	copy($file, $new_path) or error_bye ("Could not copy original audio file", "Could not copy $file to $new_path: $!");
    }
    $file = $new_path;
}

#Convert everything to MP3
my %temp_dir;
foreach my $file (@files) {
  my ($pathbase, $ext) = filebase_split($file);
  if ((lc $ext) ne 'mp3') {
    my $file_display_name = filepath_base($file);
    print "Determining original bitrate for $file_display_name\n";
    my $bitrate = file_bitrate($file) || 192;
    $bitrate =~ /^\d+$/ or error_bye("Unexpected bitrate format", $bitrate);
    print "Converting $file_display_name to mp3 at $bitrate kbps\n";
    $temp_dir{convert} ||= tempdir();
    my $temp_file;
    {
      no warnings;
      (undef, $temp_file) = tempfile('audibleturkXXXXXX', SUFFIX => '.mp3', DIR => $temp_dir{convert}, OPEN => 0); 
    }
    shell_safe($temp_file) or error_bye("Unsafe tempfile name", $temp_file);
    system("ffmpeg -i '$file' -acodec libmp3lame -ab ${bitrate}k -ac 2 '$temp_file' 2> /dev/null") == 0 or error_bye("Could not convert the file $file", "$? / $!");
    $file = $temp_file;
  }
}

#Merge files together
my $wrap_file_base =  "$config{local}/$project_name/audio/$project_name";
my $wrap_file = $wrap_file_base . '.all.mp3'; 
if (@files > 1) {
    print "Merging audio\n";
    my $files = "'$wrap_file_base' from " . join(", ", map { "'$_'" } @files);
    system("mp3wrap '$wrap_file_base' " . join(' ', map { "'$_'" } @files)  . " > /dev/null") == 0 or error_bye("Could not join audio files together","$files: $? / $!");
    my $wrap_file_temp = $wrap_file_base . '_MP3WRAP.mp3';
    move($wrap_file_temp, $wrap_file) or error_bye("Could not move file", "$wrap_file_temp to $wrap_file: $!");
} else {
    my $orig_file = $files[0];
    copy($orig_file, $wrap_file) or error_bye("Could not move file", "$orig_file to $wrap_file: $!");
}

#Split files into uniform bits
print "Splitting audio into uniform bits\n";
#We have to cd into the wrapfile directory and do everything there because
#mp3splt is absolutely retarded at handling absolute directory paths
my ($wrap_file_dir, $wrap_file_end) = filepath_split($wrap_file);
$wrap_file_dir =~ s/\/$//;
my $cmd = "cd '$wrap_file_dir' && mp3splt -t $min_dot_seconds -o '$project_name." . '@m.@s' . "' '$wrap_file_end' > /dev/null 2> /dev/null";
system($cmd) == 0 or error_bye("Could not split audio", "$? / $!");
opendir(my $dh, $wrap_file_dir) or error_bye("Could not read temp dir", "$wrap_file_dir: $!");
my @output_files = grep { "$wrap_file_dir/$_" ne $wrap_file } grep { -f "$wrap_file_dir/$_" } readdir($dh);
closedir $dh;
shell_safe($_) or error_bye("Unsafe file name", $_) foreach @output_files;
@output_files = sort { filepath_sortable_mp3splt($a) <=>  filepath_sortable_mp3splt($b) } @output_files;

#SCP files to remote server
#Randomize remote file names so they're unguessable
foreach my $file (@output_files) {
    my ($base, $ext) = filebase_split($file);
    my $remote_name = $config{randomize} ? "$base." . String::Random->new->randregex('[A-Z]{6}') . ".$ext" : $file; 
    print "Uploading $file to $config{scp} as $remote_name\n";
    system("scp '$wrap_file_dir/$file' '$config{scp}/$remote_name' > /dev/null") == 0 or error_bye("Could not upload file", "$file as $remote_name: $? / $!");
    $file = $remote_name;
}

#Process @voices args for insertion into CSV
foreach my $voice (@voices) {
    my ($name, $description) = split /,\s*/, $voice, 2;
    $description = '' if not defined $description;
    $voice = {
	name => $name,
	description => $description,
    }
}

#Process @unusual args for insertion into CSV
@unusual = map { split /,\s*/, $_ } @unusual;

#Make CSV file
#(for Amazon Mechanical Turk)
my $csv_path = "$config{local}/$project_name/csv/assignment.csv";
my $csv = Text::CSV->new({ eol => "\n" }) or error_bye("Cannot use CSV module", Text::CSV->error_diag);
open(my $fh, '>', $csv_path) or error_bye("Could not write CSV file", "$csv_path: $!");
$csv->print($fh, ['url','unusual', (map { ("voice$_", "voice${_}title") } 1 .. scalar(@voices))]);
$csv->print($fh, [ "$config{url}/$_", join(', ', @unusual), map { $_->{name}, $_->{description} } @voices ]) foreach @output_files;
close $fh or error_bye("Trouble finalizing write to CSV file", "$csv_path: $!");
print "Wrote assign.csv to $config{local}/$project_name/csv\n";

print "Opening project folder $config{local}/$project_name via AppleScript...\n";
system("open '$config{local}/$project_name'") == 0 or error_bye("Could not open folder in Finder", "$config{local}/$project_name: $!/$?");

print "Deleting temp files...\n";

clean_up();

print "Done.\n";

sub clean_up{
  my ($quiet) = @_;
  my $err;
  remove_tree(values %temp_dir, { error => \$err });
  if ($err && @$err) {
    my @error = ("Could not remove temp directories", join('; ', map { my ($file, $file_err) = %$_; "$file: $file_err" } @$err));
    warn(join(': ', @error));
    error_box(@error) unless $quiet;
  }
}

sub config_file{
  my %new_config = @_;
  my $yaml;
  open(my $fh, '<', "$ENV{HOME}/.audibleturk") or error_bye("Could not open required config file $ENV{HOME}/.audibleturk", $!);
  $yaml .= $_ while <$fh>;
  close $fh;
  my ($config) = YAML::Load($yaml);
  if (keys %new_config) {
    $config->{$_} = $new_config{$_} foreach keys %new_config;
    $yaml = YAML::Dump($config);
    open($fh, '>', "$ENV{HOME}/.audibleturk") or error_bye("Could not write to config file", "$ENV{HOME}/.audibleturk: $!");
    print $fh $yaml;
    close $fh or error_bye("Could not close config file", "$ENV{HOME}/.audibleturk: $!");
  }
  return %$config;
}

sub error_bye{
  my ($error, $details) = @_;
  $details ||= '';
  clean_up(1);
  error_box($error, $details);
  die "$error: $details";
}

sub error_box{
  my ($error, $details) = @_;
  $details ||= '';
  $error = shell_sanitize($error);
  $details = shell_sanitize($details);
  $error = "$error:" if $details;
  `$Dialoger msgbox --no-newline --title "Error" --text '$error' --informative-text '$details' --button1 "Ok"`;
}

#Return value formatted for mp3splt's weird -t format
sub to_min_seconds{
  my ($time) = @_;
  my $split_seconds = to_seconds($time);
  my $min = floor($split_seconds/60);
  my $sec = $split_seconds % 60;
  return "$min.$sec";
}

sub to_seconds{
  my ($time) = @_;
  my $split_seconds = $time =~ /(?:(\d+):)?(\d+):(\d\d)(\.(\d+))?/ ? (($1 ? ($1 * 60 * 60) : 0) + ($2 * 60) + $3 + ($4 ? "0.$4" : 0)) : $time;
  ($split_seconds) = $split_seconds =~ /(\d+)/ or return;
  return $split_seconds;
}

sub clean_temp_dir{
  my $dir = tempdir();
  shell_safe($dir) or error_bye("Unsafe tempdir name", $dir);
  $dir =~ s/\/$//;
  return $dir;
}

#Returned string should ONLY be used within single quotes
sub shell_sanitize{
  my ($text) = @_;
  $text =~ s/\\//g;
  $text =~ s/'//g;
  return $text;
}

sub shell_safe{
  my ($text) = @_;
  return not $text =~ /['\\]+/;
}

#split the file extension off from the end of the filename
sub filebase_split{
  my ($filepath) = @_;
  my ($file_base, $file_ext) = $filepath =~ /(.+)\.(\w+)$/;
  return ($file_base, $file_ext);
}

#split the path info off from the start of the filename
sub filepath_split{
  my ($filepath) = @_;
  my ($volume, $dir, $file) = File::Spec->splitpath($filepath);
  return ("$volume$dir", $file);
}
#get filename w/extension without the path info
sub filepath_base{
  my ($filepath) = @_;
  my @path  = filepath_split($filepath);
  return $path[1];
}

sub filepath_sortable{
  my ($filepath) = @_;
  my $sortable = $filepath;
  $sortable =~ s/[_\+\.\-]//g;
  $sortable = lc $sortable;
  return $sortable || $filepath;
}

sub filepath_sortable_mp3splt{
    my ($filepath) = @_;
    my ($start_min, $start_sec) = filepath_base($filepath) =~ /\.(\d+)\.(\d\d)\.mp3/i or error_bye("Could not extract minutes, seconds from file", filepath_base($filepath));
    my $seconds = to_seconds("$start_min:$start_sec");
    return $seconds;
}

sub file_bitrate{
    my ($file) = @_;
    shell_safe($file) or error_bye("Unsafe file name", $file);
    my $info = `ffmpeg -i $file 2>&1`;
    my ($bitrate) = $info =~ /(\d+) kb\/s/;
    return $bitrate;
}
