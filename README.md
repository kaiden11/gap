# gap

Statistical log gap analysis.

## Usage

    gap.pl [options] [file [file]]


## Description

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

## Options

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
