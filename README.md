NAME
====

IO::Slice - restrict reads to a range in a file

SYNOPSIS
========

    use IO::Slice;

    # Define a slice based on a file
    my $sfh = IO::Slice->new(
       filename => '/path/to/file',
       offset   => 13,
       length   => 16,
    );

    # Ditto, based on a previously available filehandle $fh. The
    # filehandle MUST be seekable.
    my $sfh = IO::Slice->new(
       fh     => $fh,
       offset => 13,
       length => 16,
    );

    # Both the filehandle and the filename can be provided. The
    # filehandle will win.
    my $sfh = IO::Slice->new(
       fh       => $fh,
       filename => '/path/to/file',
       offset   => 13,
       length   => 16,
    );

Whatever the method to create it, `$sfh` can be used as any other
filehandle, mostly.

ALL THE REST
============

Want to know more? [See the module's documentation](http://search.cpan.org/perldoc?IO::Slice) to figure out
all the bells and whistles of this module!

Want to install the latest release? [Go fetch it on CPAN](http://search.cpan.org/dist/IO-Slice/).

Want to contribute? [Fork it on GitHub](https://github.com/polettix/IO-Slice).

That's all folks!

