#!/usr/bin/perl


use strict;
use warnings;

#Parsing argument values
use Getopt::Long;
#Date parsing and manipulation
use Date::Manip;

use Data::Dumper;

#Storage for command line flags
my(%options);
my(@fields, $date_field,$date_value);

#Window of timestamp differences, in seconds
my(@differences);

#Temporary store for previous date value and previous record
my($previous_date,$previous_line);


my($last_running_stats) = 0;
my($lines_read) = 0;

#Usage routine
sub usage_die {
  die(<<EOUD
Usage: gap.pl [options] [file [file]]
---
Description:
  Provides rough statistical analysis on date values from
  date/timestamped files. The intent is to identify gaps
  in logs, implying potential gaps in service, by looking
  at statistically aberrant jumps in time from line to line.

  Can either accept filenames from the argument list, or
  in the absence of filenames, will attempt to read from
  STDIN.

  The program uses Perl's Date::Manip module to attempt
  to parse date/times. It relies solely on this, and attempts
  no further parsing methods unless called using the
  --timestamp flag, in which case it will attempt to parse
  the date field as a timestamp.

Options:
  --delimiter=S
    Similar to the -d flag for the Unix cut utility,
    this can be used to specify the delimiter used to
    divided the record into seperate fields.

  --field=[range, [range]]
    Similar to the field specification for the Unix cut
    utility. Possible formats:
      N
      M-
      M-N
      -N

    If undefined, the program will use the entire line
    as a date, and attempt to parse it.

  --within=N
    'within' determines what the algorithm considers to
    be statistically aberrant. To define something as 
    normal, the algorithm finds the mean time difference
    for the past M records, determined by --window, and
    the standard deviation of those differences, and
    tests to see if a value is within
      [ mean-N*sttdev,mean+N*stddev]
    If a value lies outside of this range, it is
    considered aberrant, and will be displayed differently
    than the rest of the output.

    A value of 1 captures about ~65% of normal values 
    (and reports 35% as aberrant), 2 captures ~75%, 3
    captures ~99%. The idea is that the higher an integer,
    the more rare that the program will report something
    being out of the ordinary, making it easier to see
    large gaps and to ignore inconsequential ones.

  --pattern
    If speed is an issue, specify a pattern to try to make
    parsing out date components a quicker process.

    Say you've got a timestamp like this:
      2010-10-03 20:03:42 AKST

    This can be parsed "automatically" using Date::Manip,
    however, this is very time consuming and CPU intensive.

    Instead, you can use a specified pattern, similar to
    strftime, to identify components as part of a regular
    expression pattern. For the example above:

      %Y-%m-%d %H:%M:%S AKST

    Note that if you specify the pattern, by default if the
    date field specified using --field does not match,
    execution will halt. Override this by using --stop-caring

  --stop-caring
    If using pattern matching, simply skip a line that doesn't match
    the pattern

  --only-outliers
    Only display lines that are statistically aberrant.

  --pretty
    Ouput ANSI Color terminals to highlight aberrant lines
    in red.

  --display-date
    Prefix the current line with the full, human readable 
    date, parsed from the line. This may result in 
    redundant date information, but is useful for when
    the date isn't always apparent from the line
    (ie, when processing timestamps).

  --window=N (N is in seconds)
    Determines the size of the last N time differences
    that will be used to determine normalcy for the
    current time difference.

  --minimum=N (N is in seconds)
    In addition to the within specifier, you can also
    specify a minimum amount of a time difference between
    the current record and the last that must be exceeded
    in order for the program to report on it.

  --maximum=N
    Same as the minimum, but just requiring an upper bound.

  --timestamp
    Instructs the program to treat the specified date field
    as a Unix epoch timestamp. This is important, as the
    Date::Manip formats do not automatically recognize
    Unix timestamps.

  --running-stats=N
    Every N seconds (default 60) show the average time between
    lines and the standard deviation.

Examples:
Piping squid access logs for a particular IP address from grep to gap.pl, limiting dates between 2009-01-06 to 2009-01-07
grep -ie "127.0.0.1" access.log | ./gap.pl --field=1 --within 2 --window 10 --timestamp --replace --minimum=400 --begin 20090106 --end 20090107

The same thing, but with a slightly different output format, and doing it for all dates
grep -ie "127.0.0.1" access.log | cut -d " " -f 1 | ./gap.pl --within 2 --window 10 --timestamp


EOUD
);

}


#Subroutine to handle --field flags
#Returns a list of fields to use to
#determine a date
sub get_fields($$) {
  my($field_expression,$number_of_fields) = @_;
  my(@ranges);
  my(@return_fields);
 
  #Get our collection of ranges, which are
  #seperated by commas in our field delimiter
  #argument 
  @ranges = split /,/, $field_expression;

  #Foreach range value given, try to parse out the range 
  foreach my $range (@ranges) {
    my($begin_field,$end_field);

    if($range =~ /^\d+$/) {
      #We're only dealing with a single field,
      #add this guy to our collection
      push @return_fields, $range; 
    }
    else {
      #Handling for N- range 
      if($range =~ /^(\d+)-$/) {
        $begin_field = $1;

        while($begin_field <= $number_of_fields) {
          push @return_fields, $begin_field;
          $begin_field++;
        }
      }
      else {
        # Handling for -M range
        if($range =~ /^-(\d+)$/) {
          $begin_field = 1;
          $end_field = $1;

          #if($end_field <= $number_of_fields) {
            while($begin_field <= $end_field) {
              push @return_fields, $begin_field;
              $begin_field++;
            }
          #}
          #else {
            #warn("End field is beyond the number of fields!\n");
          #}
        }
        else {
          #Handling for N-M range
          if($range =~ /^(\d+)-(\d+)$/) {
            $begin_field = $1;
            $end_field = $2;

            if($begin_field <= $end_field) { 
              while($begin_field <= $end_field) {
                push @return_fields, $begin_field;
                $begin_field++;
              }
            }
            else {
              warn("Invalid field range, first field must be less than or equal to second field in range\n");
              return undef;
            }
          }
          else {
            warn("Invalid field or field range specified!\n");
            return undef;
          }
        }
      }
    }
  }

  #Make unique our selected fields, and sort numerically
  my %tmp = map { $_ => 1 } @return_fields;
  @return_fields = keys %tmp;
  @return_fields = sort { $a <=> $b } @return_fields;

  return @return_fields;
}


sub pattern_create_dt {
    my($matches) = @_;

    my $ret = "";

    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        localtime();

    # 2010120610:33:12 
    $ret .= ( exists $matches->{full_year} && $matches->{full_year} ? 
        $matches->{full_year} 
        : 
        $year + 1900 
    );

    if(exists $matches->{full_month} && exists $matches->{abbrev_month} ) {
        die("One or the other: full_month abbrev_month\n");
    } else {
        if(exists $matches->{full_month} ) {
            $ret .= ( exists $matches->{full_month} && $matches->{full_month} ? $matches->{full_month} : sprintf("%02d", $mon+1 ) );
        }

        if(exists $matches->{abbrev_month} ) {
            my %month_abbrev = (
                'jan' => 1  ,
                'feb' => 2  ,
                'mar' => 3  ,
                'apr' => 4  ,
                'may' => 5  ,
                'jun' => 6  ,
                'jul' => 7  ,
                'aug' => 8  ,
                'sep' => 9  ,
                'oct' => 10 ,
                'nov' => 11 ,
                'dec' => 12 ,
            );

            unless( exists $month_abbrev{lc($matches->{abbrev_month})} ) {
                die("Unknown abbreviated month value: $matches->{abbrev_month}\n");
            } else {
                $ret .= $month_abbrev{lc($matches->{abbrev_month})};
            }
        }
    }

    $ret .= ( exists $matches->{full_day_of_month} && $matches->{full_day_of_month} ? $matches->{full_day_of_month} : sprintf("%02d", $mday+1 ) );

    $ret .= ( exists $matches->{full_hour} && $matches->{full_hour} ? $matches->{full_hour} : sprintf("%02d", $hour ) );
    $ret .= ":";
    $ret .= ( exists $matches->{full_minute} && $matches->{full_minute} ? $matches->{full_minute} : sprintf("%02d", $min ) );
    $ret .= ":";
    $ret .= ( exists $matches->{full_second} && $matches->{full_second} ? $matches->{full_second} : sprintf("%02d", $sec ) );


    return $ret;
}

#Take the sume of an array
sub sum {
  my $sum = 0;
  foreach (@_) {
    $sum += $_;
  } 
  return $sum;
}

#Take the average of an array
sub average {
  if(scalar(@_) == 0) {
    return 0;
  }
  else {
    return sum(@_) / scalar(@_);
  }
}

#Take the standard deviation of an array
sub stddev {
  my $average = average(@_);
  my $accum = 0;
  foreach (@_) {
    $accum += ($_ - $average)**2; 
  }
  return sqrt((1/scalar(@_)) * $accum);
}

#Determine whether a date value is between two other date
#values
sub within_date($$$) {
  my($date_value,$begin_date,$end_date) = @_;

  if($begin_date) {
    #warn("begin cmp: $date_value cmp $begin_date ==",($date_value cmp $begin_date),"\n");
    if(($date_value cmp $begin_date) == -1) {
      return 0;
    }
  }

  if($end_date) {
    #warn("end cmp:",($date_value cmp $end_date),"\n");
    if(($date_value cmp $end_date) == 1) {
      return 0;
    }
  }

  return 1;
}

#Determine whether an integer is between (inclusive)
#two other integers
sub within_int($$$) {
  my($int, $lower, $upper) = @_;

  if($lower) {
    if($int < $lower) {
      return 0;
    }
  }
  
  if($upper) {
    if($int > $upper) {
      return 0;
    }
  }

  return 1;
}



%options = (
              field => undef,
              delimiter => " ",
              timestamp => 0,
              pretty => 0,
              "display-date" => 0,
              "only-outliers" => 0,
              "running-stats" => undef,
              window => 10,
              within => 2,
              begin => undef,
              end => undef,
              minimum => undef,
              maximum => undef,
              pattern => undef,
              'pattern-re' => undef,
              'stop-caring' => undef,
              help => 0
            );

my $rv = GetOptions(  "delimiter:s" => \$options{delimiter}, 
                      "timestamp" => \$options{timestamp},
                      "pretty" => \$options{pretty},
                      "display-date" => \$options{"display-date"},
                      "only-outliers" => \$options{"only-outliers"},
                      "running-stats:60" => \$options{"running-stats"},
                      "field:s" => \$options{field},
                      "window:i" => \$options{window},
                      "within:i" => \$options{within},
                      "begin:s" => \$options{begin},
                      "end:s" => \$options{end},
                      "minimum:i" => \$options{minimum},
                      "maximum:i" => \$options{maximum},
                      "pattern:s" => \$options{pattern},
                      "stop-caring" => \$options{'stop-caring'},
                      "help" => \$options{help},
                   );

if(!$rv) {
  warn("Unable to parse options!\n");
  usage_die();
}
else {

  #Die and print help if you asked for it
  if($options{help}) {
    usage_die();
  }

  #Die and print help if you don't understand statistics
  if($options{within} < 1) {
    usage_die();
  }

  if(length($options{delimiter}) <= 0) {
    warn("Cannot use zero-length string as a delimiter!\n");
    usage_die();
  }


  my($begin_date,$end_date) = (undef,undef);

  if(defined $options{begin}) {
    $begin_date = ParseDate($options{begin});

    if(!$begin_date) {
      die("Unable to parse begin: $options{begin}\n");
    }
  }

  if(defined $options{end}) {
    $end_date = ParseDate($options{end});

    if(!$end_date) {
      die("Unable to parse begin: $options{end}\n");
    }
  }


  if( $options{'pattern'} ) {
    # Pattern specified. Attempt to turn it into a reasonable regular expression.

    my %translation = (
        '%Y' => '(?<full_year>\d{4})',
        '%m' => '(?<full_month>\d{2})',
        '%d' => '(?<full_day_of_month>\d{2})',
        '%H' => '(?<full_hour>\d{2})',
        '%M' => '(?<full_minute>\d{2})',
        '%S' => '(?<full_second>\d{2})',
        '%b' => '(?<abbrev_month>jan|feb|mar|apr|may|jun|jul|aug|sept|nov|dec)',
    );

    my $tmp_pattern = $options{'pattern'};

    foreach my $component ( keys %translation ) {
      $tmp_pattern =~ s/$component/$translation{$component}/g;
    }

    $tmp_pattern =~ s/\//\\\//g;

    print "Parsed pattern into: $tmp_pattern\n";
    $options{'pattern-re'} = qr/$tmp_pattern/i;
  }

  #Read from filenames remaining on ARGV, or from
  #STDIN in their absence
  while(<>) {
    chomp $_;

    $lines_read++;

    #Split, based on our delimiter flag, or, if the delimiter
    @fields = split(/\Q$options{delimiter}\E+/i, $_);

    my(@selected_fields,@selected_indexes);

    #Find the applicable selected indicies for our
    #line
    if(defined $options{field}) {
      @selected_fields = get_fields($options{field},scalar(@fields));
      @selected_indexes = map { $_-1} @selected_fields;
    }

    #If our field is specified and the indexes exist within
    #the @fields array, select them out and then join them
    #together to be used as a date value 
    if(defined $options{field} && (grep { $_ >= 0 && $_ <= $#fields } @selected_indexes)) {
      $date_field = join(" ", @fields[@selected_indexes]);
    }
    else {
      #Otherwise, just use the whole line
      $date_field = $_;
    }

    #If we're in timestamp mode, try to handle the date value as such 
    if($options{timestamp}) {
      $date_value =  ParseDateString("epoch " . int($date_field));
    }
    else {
      if( $options{pattern} ) {
        if( $date_field =~ m/$options{'pattern-re'}/ ) {

          $date_value =  pattern_create_dt( \%+ );
        } else {
          if( $options{'stop-caring'} ) {
            next;
          } else {
            die("Specified a pattern, but date field didn't match: '$date_field'. Stopping\n");
          }
        }
      } else {
        #Otherwise, parse using Date::Manip
        $date_value = ParseDate("$date_field");
      }
    }

    my $difference;
    my $error;

    my $is_aberrant = 0;

    if(defined $previous_date) {
      $difference = int( Delta_Format( DateCalc( $previous_date, $date_value, \$error), 0, '%st' ) );
    }
    else {
      $difference = 0;
    }

    my( $avg, $stddev );

    #Maintain our window
    if(scalar(@differences) >= $options{window}) {
      #Find the average and standard deviation on the @differences array
      $avg = average(@differences);
      $stddev = stddev(@differences);
  
      #If the difference is within the min/max range flags 
      if(within_int($difference, $options{minimum},$options{maximum})) { 
        #If it is also considered aberrant from the data set
        if($difference < ($avg - $options{within}*$stddev) || $difference > ($avg + $options{within}*$stddev)) {
          $is_aberrant = 1;
        }
        else {
          #print("$difference is within [",($avg - $options{within}*$stddev),",",($avg + $options{within}*$stddev),"]\n");
        }
      }
      #Take the last element off of the @differences array
      shift @differences;

      if( $options{'running-stats'} && $options{'running-stats'} > 0 && ( (time() - $last_running_stats) >= $options{'running-stats'} )  ) {
        printf("RUNNING STATS: Last Date Read=%s, Lines Read=%d, Average Time Between Lines = %.1f, Standard Deviation = %.1f\n", 
          UnixDate($date_value,"%O"), 
          $lines_read, 
          $avg, 
          $stddev 
        );

        $last_running_stats = time();
      }

    }

    #If we care about this date
    if(within_date($date_value,$begin_date,$end_date)) {
      my $tmp = UnixDate($date_value,'%c');
      my $print_prefix = "";
      my $print_suffix = "";

      if($options{"display-date"}) {
        $print_prefix .= "$tmp ";
      } 

      if($options{pretty}) {
        if($is_aberrant) {
          $print_prefix = "\e[0;31m" . $print_prefix; 
          $print_suffix = "\e[0m";
        }
      }

      if($options{"only-outliers"}) {
        if($is_aberrant) {
          print $print_prefix, "[+$difference] ", $_, $print_suffix, "\n";
        } 
      }
      else {
        print $print_prefix, "[+$difference] ", $_, $print_suffix, "\n";
      }
    }

    #Push the current difference onto our window
    push @differences, $difference;

    #Set the current date/line to the previous date/line
    $previous_date = $date_value;
    $previous_line = $_;

  }

  #We may not have read enough lines to establish the 
  #specified window. If so, report it, and exit in an
  #error state.
  if(scalar(@differences) < $options{window}) {
    die("Never reached window size! Either adjust your window flag (currently $options{window}), or read more data.\n");
  }
}