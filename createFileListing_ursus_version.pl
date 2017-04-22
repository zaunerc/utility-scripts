#!/usr/bin/perl -w

############################################################
# ABOUT
#
# author: czauner
#
# last change: 16. Nov. 2010
#
# info: Creates a file listing. The good file extensions should
#       be specified one per line (without a preceding dot). The
#       extensions are converted to lowercase. Lines beginning with
#       a hash mark are ignored.
#
#       For each evidence item an evidence info file is processed.
#	    See zuordnung.txt for an example.
#       This file must be located on the same level as the evidence
#       directory.
#
#       - FTK imager uses UCS-2 LE to encode the text.
#       - Fields can be blank.
#       - chomp() odes NOT remove the CR character. At least
#         when using ActivePearl.
#
# TODO: - Write man page.
#       - Write total size of bytes and GiB to report file.
#
############################################################

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Find;

my $scriptName = basename($0);
die "usage: $scriptName <dir to search for file listings> <file for file listing> <file for report> <file of good extensions> <dir filter file>\n" unless @ARGV == 5;

# 0 (off) - 3 (very verbose) 
my $debug = 3;
# delimiter
my $del = "\t";
# Used to fill in blank fields
my $emptyString = "X";
# should files withouth extensions be filtered out?
my $filterNoExtension = 1;
# file to use as evidence info. The first line should contain the name
# of the custodian. The second should contain the place.
my $evidenceInfoFileName = "zuordnung.txt";
my $encodingIn = "UCS-2LE";
my $encodingOut = "UTF-8";

my $dir = $ARGV[0];
my $listingOut = $ARGV[1];
my $report = $ARGV[2];
my $extFile = $ARGV[3];
my $dirFilterFile = $ARGV[4];

my @listingOut;
my $fh_report;
my $fh_listingOut;
my $evidenceCustodian;
my $evidencePlace;

# Counters
my $processedEntries = 0;
my $processedFiles = 0;
my $entriesAccepted = 0;
# FIXME: not implemented; should count ill formatted lines
my $entriesIgnored = 0;
my $entriesFilteredBadExt = 0;
my $entriesFilteredNoExt = 0;
my $entriesFilteredBadPath = 0;

# good extensions => 1, bad extensions => 0
my %extensions;
my $msg = "";

my $totalBytes = 0;
my @statsMessage = "";

# DIRFILTER
my @dirFilter;
my $fh_dirFilterFile;

############################################################
# FUNCTIONS

sub eachFileListing {
		my $fileName = $_;
		my $fullPath = File::Spec->rel2abs($fileName);
		my @listingIn;
		my $fh_listingIn;
		my $numberOfFields;
		my $listingGoodBytes = 0;
		my $listingGoodFiles = 0;
		
		# ignore non-csv files
		return if  not ($fileName =~ m/^.*\.csv$/);
		
		$processedFiles++;
		
		$msg = "Processing file >$fullPath<\n";
		print $msg;
		print $fh_report $msg;
		
		# STEP get additional evidence info
		
		setEvidenceInfo($fullPath);
		
		# STEP process the file
		
		# read in the lines of the file
		open ($fh_listingIn, "<:encoding($encodingIn)", $fullPath) or die "$!";
		# chomping is not neccessary because we 
		# remove all whitespace later on.
		@listingIn = <$fh_listingIn>;
		close $fh_listingIn;	

		# get the number of the fields from the header
		my @headerLine = split(/\t/,shift(@listingIn));
		$numberOfFields = scalar(@headerLine);
		print "[I2] CSV file has $numberOfFields fields\n" if $debug > 1;
		
		# the header line has already been removed
		my $idx = 1;
		foreach(@listingIn) {
		
			my $idx++;
		
			# fields directly read from the CSV file
		
			my $entry_fileName = $emptyString;
			my $entry_fullPath = $emptyString;
			my $entry_size = 0;
			my $entry_created = $emptyString;
			my $entry_modified = $emptyString;
			my $entry_accessed = $emptyString;
			my $entry_isDeleted = $emptyString;
			
			# newly created fields
			
			my $entry_commonPath = $emptyString;
			my $entry_extension = $emptyString;
			my $entry_evidenceID = $emptyString;

			$processedEntries++;
			# All CSV files in one directory
			$entry_evidenceID = basename($fullPath);
			# Each CSV file in it's own directory
			#$entry_evidenceID = basename(dirname($fullPath));
			
			my @fields = split(/\t/);

			if (scalar(@fields) != $numberOfFields) {
				print "[E] Line $idx in CSV file >$fullPath< has more or less fields than the header line. Ignoring it.\n";
				print $fh_report "[E] Line $idx in CSV file >$fullPath< has more or less fields than the header line. Ignoring it.\n";				
				next;
			}
			
			# Remove ANY whitespace at the end of each field. 
			# chomp() seems to have problems with UCS-2 LE
			# encoding. It removes only the last byte.
			foreach(@fields) {
				$_ =~ s/\s*$//g; 
			}
			
			if (length($fields[0]) > 0) { $entry_fileName = $fields[0]; }
			if (length($fields[1]) > 0) { $entry_fullPath = $fields[1]; }
			if (length($fields[2]) > 0) { $entry_size = $fields[2]; }
			if (length($fields[3]) > 0) { $entry_created = $fields[3]; }
			if (length($fields[4]) > 0) { $entry_modified = $fields[4]; }
			if (length($fields[5]) > 0) { $entry_accessed = $fields[5]; }
			if (length($fields[6]) > 0) { $entry_isDeleted = $fields[6]; }

			if ($entry_fileName =~ m/^.*\.(\w*)$/) {
				$entry_extension = lc($1);
			}

			# STEP filtering by path

			my $ignoreEntry = 0;
			foreach(@dirFilter) {
				my $pattern = $_;
				if ($entry_fullPath =~ m/.*$pattern.*/) {
					$ignoreEntry = 1;
					$entriesFilteredBadPath++;
				}
			}
			next if $ignoreEntry == 1;
			
			# STEP filtering by file extensions

			if ($entry_fileName =~ m/^.*\.(\w*)$/) {
				if (not exists $extensions{lc($1)}) {
					$entriesFilteredBadExt++;
					next; 
				}
			} elsif ($filterNoExtension) {
				$entriesFilteredNoExt++;
				next;
			}


			
			# common path begin
			
			if ($entry_fullPath =~ m/^(.*?\\.*?\\.*?\\.*?\\).*$/) {
				$entry_commonPath = $1;
			}

			# common path end
			
			# count the bytes
			$totalBytes += $entry_size;
			$listingGoodBytes += $entry_size;
			$listingGoodFiles++;
			
			# STEP write results to listing
			
			$entriesAccepted++;
			print $fh_listingOut 
				"$entry_fileName".$del.
				"$entry_fullPath".$del.
				"$entry_size".$del.
				"$entry_created".$del.
				"$entry_modified".$del.
				"$entry_accessed".$del.
				"$entry_isDeleted".$del.
				"$entry_evidenceID".$del.
				"$evidenceCustodian".$del.
				"$evidencePlace".$del.
				"$entry_extension".$del.
				"$entry_commonPath\n";
		}

		$msg = basename($fullPath) . $del . $listingGoodBytes . $del . ($listingGoodBytes/1024/1024/1024) . $del . $listingGoodFiles . "\n";
		print $msg;
		push(@statsMessage, $msg);
}

# Arguments
#
#   0: Absolute path to CSV file.
#
sub setEvidenceInfo {
	my $evidenceInfo = File::Spec->catdir( dirname(dirname($_[0])), $evidenceInfoFileName );
	my $fh_evidenceInfo;
	my @evidenceInfoLines;
	
	$evidenceCustodian = $emptyString;
	$evidencePlace = $emptyString;
	
	print "[I2] Info file: >$evidenceInfo<\n" if $debug > 1;
	
	open ($fh_evidenceInfo, "<", $evidenceInfo) or die "$!";
	
	@evidenceInfoLines = <$fh_evidenceInfo>;
	
	# Remove any trailing whitespace.
	foreach(@evidenceInfoLines) {
		$_ =~ s/\s*$//g; 
	}
	
	foreach (@evidenceInfoLines) {
		if ($_ =~ m/^custodian\t(.*)$/) {
			$evidenceCustodian = $1;
		} elsif ($_ =~ m/^place\t(.*)$/) {
			$evidencePlace = $1;
		}
	}
	
	close ($fh_evidenceInfo);
}

sub getDirFilter {
	
	my $fh_dirFilterFile;
	my @dirFilter;
	
	open ($fh_dirFilterFile, "<", $dirFilterFile) or die "$!";
	
	while (<$fh_dirFilterFile>) {
		# ignore comments
		next if $_ =~ m/^#/;	
		push(@dirFilter, $_);
	}

	foreach(@dirFilter) {
			$_ =~ s/\s*$//g;			
	}
	
	close ($fh_dirFilterFile);
}

sub getExtensions {
	
	my $fh_extFile;
	my @extArray;
	
	open ($fh_extFile, "<", $extFile) or die "$!";
	
	@extArray = <$fh_extFile>;
	foreach(@extArray) {
			$_ =~ s/\s*$//g; 
	}
	
	foreach (@extArray) {
		# ignore comments
		next if $_ =~ m/^#/;
		$extensions{lc($_)} = 1;
	}
	
	close ($fh_extFile);
}

# FUNCTIONS
############################################################

open ($fh_report, ">", $report) or die "$!";
open ($fh_listingOut, ">:encoding($encodingOut)", $listingOut) or die "$!";
print $fh_listingOut 
	"Dateiname".$del.
	"Pfad".$del.
	"Größe (Byte)".$del.
	"Erstellt".$del.
	"Modifiziert".$del.
	"Zugegriffen".$del.
	"Gelöschte Datei".$del.
	"Evidence ID".$del.
	"Beschuldigter".$del.
	"Ort".$del.
	"Erweiterung".$del.
	"Common path\n";

getDirFilter();
getExtensions();

print @dirFilter;

find (\&eachFileListing, $dir);

$msg = "Processed $processedFiles files.\n";
print $msg;
print $fh_report $msg;

$msg = "Processed $processedEntries entries. $entriesIgnored entries were ignored.\n$entriesFilteredBadExt had bad extensions.\n$entriesFilteredNoExt were filtered because they had no extension.\n$entriesFilteredBadPath were filtered because they had a bad path.\n$entriesAccepted entries were accepted.\n";
print $msg;
print $fh_report $msg;

$msg = "Bytes filtered out: $totalBytes (" . $totalBytes / 1024 / 1024 / 1024 . " GiB)\n";
print $msg;
print $fh_report $msg;

print $fh_report "\nPer file listing statistics (tab separated) BEGIN ***\n\n";
print $fh_report "Name of listing" . $del . "Total bytes accepted" . $del . "Total GiB accepted" . $del . "Number of accepted files\n";
print $fh_report @statsMessage;
print $fh_report "\nPer file listing statistics (tab separated) END ***\n\n";

close $fh_report;
close $fh_listingOut;
