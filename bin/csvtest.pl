#!/usr/bin/perl

use strict;
use warnings;
use Text::CSV;

my @rows = (['fee', 'fi'],['fo', 'fum'],['blood','irishman']);
my $csv = Text::CSV->new ( { eol => "\n" } )  # should set binary attribute.
    or die "Cannot use CSV: ".Text::CSV->error_diag ();
#$csv->eol ($/);
open my $fh, ">", "$ENV{HOME}/Downloads/new.csv" or die "new.csv: $!";
$csv->print ($fh, $_) for @rows;
close $fh or die "new.csv: $!";
 
