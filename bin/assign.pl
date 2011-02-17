#!/opt/local/bin/perl

##TODO
#Verify all URLs to make sure there are no 404s
#Add random string to filenames to make URLs unguessable

use strict;
use warnings;

use File::Temp qw(tempfile tempdir);
use File::Path 'remove_tree';
use File::Copy;
use File::Spec;
use POSIX qw(floor);
use Text::CSV;
use String::Random;
use Mac::AppleScript 'RunAppleScript';

my $Dialoger = '/Applications/CocoaDialog.app/Contents/MacOS/CocoaDialog';

my @files = @ARGV;
@files or error_bye("Drag audio files onto the icon");

#Need files in proper order before joining them
@files = sort { filepath_sortable($a) cmp filepath_sortable($b) } @files;
#Need file extensions so we know what files need to be converted to mp3
filebase_split($_) or error_bye("You need a file extension on the file '$_'") foreach @files;
#Escape file names so they can safely be passed to shell within single quotes 
shell_safe($_) or error_bye("Unsafe file name", $_) foreach @files;

my %config = config_file();
$config{$_} or error_bye("Required param '$_' missing from config file", "$ENV{HOME}/.audibleturk") foreach qw(scp url);
#my @fails = $config{scp} =~ /[^\w\s_\@\/\.\:\-]+/g;
#print "DEBUG fail $_\n" foreach @fails;
$config{scp} =~ /^[\w\s_\@\/\.\:\+\-]+$/ or error_bye("Unexpected scp format in config file", "$ENV{HOME}/.audibleturk");
if ($config{local}) {
  $config{local} =~ s/^~\/?/$ENV{HOME}/;
  $config{local} = "$ENV{HOME}/$config{local}" if $config{local} =~ /^[^\/]/;
  $config{local} =~ s/\/$//;
}
$config{local} ||= "$ENV{HOME}/Desktop";

foreach (qw(scp url local)){
    $config{$_} =~ s/\s+$//;
    $config{$_} =~ s/\/$//;
}

shell_safe($config{local}) or error_bye("Unsafe dir name", $config{local});
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
my $default_interval = $config{last_split_interval} || $config{default_split_interval} || '1:00';
$default_interval =~ /^[\d\:\s\.]+$/ or error_bye("Unexpected format to default split interval '$default_interval'");
my $min_dot_seconds;
until ($min_dot_seconds) {
  my $dialog_input = `$Dialoger standard-inputbox --title "Length" --no-newline --informative-text "Split audio every (hh:mm:ss)" --text '$default_interval'`;
  my ($button, $time) = split /\n/, $dialog_input, 2;
  $button == 1 or exit;
  $min_dot_seconds = to_min_seconds($time) or error_box("Did not understand the time '$time'");
  config_file('last_split_interval' => $time) if $min_dot_seconds;
}


#Get base name for mp3s we'll be outputting
my ($default_name) = filebase_split(filepath_base($files[0]));
$default_name =~ s/(\w+)\d+$/$1/;
my $project_name;
until ($project_name) {
  my $dialog_input = `$Dialoger standard-inputbox --title "Name" --no-newline --informative-text "Base name for mp3s:" --text '$default_name'`;
  my $button;
  ($button, $project_name) = split /\n/, $dialog_input, 2;
  $button == 1 or exit;
  $project_name =~ s/\s/_/g;
  $project_name =~ s/[^\w_-]//g;
  if ($project_name =~ /\w/) {
    if (mkdir "$config{local}/$project_name") {
      mkdir "$config{local}/$project_name/$_" or error_bye("Failed to create folder", "$config{local}/$project_name/$_") foreach qw(audio csv originals etc);
    } else {
      if ($! =~ /file exists/i) {
	error_box("Name taken, please choose another", "Folder already exists at $config{local}/$project_name");
	$project_name = '';
      } else {
	error_bye("Failed to create folder", "$config{local}/$project_name: $!");
      }
    }
  } else {
    error_box('Name must contain one letter or number');
    $project_name = '';
  }
}

#Copy audio files to 'originals' folder
foreach my $file (@files){
    my $base = filepath_base($file);
    my $new_path = "$config{local}/$project_name/originals/$base";
    copy($file, $new_path) or error_bye ("Could not copy original audio file", "Could not move $file to $new_path: $!");
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
    system("ffmpeg -i $file -acodec libmp3lame -ab ${bitrate}k -ac 2 '$temp_file' 2> /dev/null") == 0 or error_bye("Could not convert the file $file", "$? / $!");
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

#Make CSV file
#(for Amazon Mechanical Turk)
my $csv_path = "$config{local}/$project_name/csv/assignment.csv";
my $csv = Text::CSV->new({ eol => "\n" }) or error_bye("Cannot use CSV module", Text::CSV->error_diag);
open(my $fh, '>', $csv_path) or error_bye("Could not write CSV file", "$csv_path: $!");
$csv->print($fh, ['url']);
$csv->print($fh, ["$config{url}/$_"]) foreach @output_files;
close $fh or error_bye("Trouble finalizing write to CSV file", "$csv_path: $!");

RunAppleScript(qq(tell application "Finder"\nopen POSIX file "$csv_path"\nend tell));
RunAppleScript(qq(tell application "Finder"\nopen folder POSIX file "$config{local}/$project_name"\nend tell));

clean_up();

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
  my %config;
  my @order;
  open(my $fh, '<', "$ENV{HOME}/.audibleturk") or error_bye("Could not open required config file $ENV{HOME}/.audibleturk", $!);
  while (<$fh>) {
    chomp;
    my ($key, $value) = split /\s+/, $_, 2;
    if ($key) {
      $key =~ s/:$//;
      $config{$key} = $value;
    }
    push @order, ($key || undef);
  }
  close $fh;
  if (keys %new_config) {
    open($fh, '>', "$ENV{HOME}/.audibleturk") or error_bye("Could not write to config file", "$ENV{HOME}/.audibleturk: $!");
    foreach my $key (@order) {
      if (defined $key) {
	print $fh "$key: " . (defined $new_config{$key} ? $new_config{$key} : $config{$key}) . "\n"; 
	delete $new_config{$key}
      } else {
	print $fh "\n";
      }
    }
    print $fh "$_: $new_config{$_}\n" foreach sort keys %new_config;
    close $fh;
  }
  return %config;
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
